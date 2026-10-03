#!/usr/bin/env ruby
# frozen_string_literal: true

# First-release preparation for Uniboard. Default execution is GET-only.
# --apply writes the reviewed listing; --submit additionally sends it to Apple.
# No mutation is retried automatically. Re-query after an ambiguous timeout.
# Credentials are read locally and never logged. Upload URLs are never logged.
# Apple API reference: https://developer.apple.com/app-store-connect/api/
# Asset flow: https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect

require 'base64'
require 'digest'
require 'json'
require 'net/http'
require 'openssl'
require 'optparse'
require 'time'
require 'uri'

module UniboardAppStoreRelease
  APP_ID = '6818750518'
  BUNDLE_ID = 'ad.neko.uniboard'
  TEAM_ID = '7P8CLHDH5G'
  PRODUCT_ID = '001084ae-fa0b-491c-b14a-2f03ad794f84'
  API_ORIGIN = 'https://api.appstoreconnect.apple.com'
  EDITABLE = %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
  SUBMITTED = %w[WAITING_FOR_REVIEW IN_REVIEW PENDING_DEVELOPER_RELEASE PENDING_APPLE_RELEASE READY_FOR_DISTRIBUTION READY_FOR_SALE PROCESSING_FOR_DISTRIBUTION].freeze
  REVIEW_STATES = %w[WAITING_FOR_REVIEW IN_REVIEW COMPLETE].freeze
  VALID_REVIEW_ITEM_STATES = %w[READY_FOR_REVIEW ACCEPTED APPROVED].freeze
  CONTACT_KEYS = %w[contactFirstName contactLastName contactPhone contactEmail].freeze
  FILES = {
    'name' => ['name.txt', 30], 'subtitle' => ['subtitle.txt', 30],
    'description' => ['description.txt', 4000], 'keywords' => ['keywords.txt', 100],
    'promotionalText' => ['promotional_text.txt', 170], 'whatsNew' => ['release_notes.txt', 4000]
  }.freeze
  PNG_SIZES = {
    'APP_IPHONE_67' => [[1260, 2736], [1290, 2796], [1320, 2868]],
    'APP_IPHONE_65' => [[1284, 2778], [1242, 2688]],
    'APP_IPAD_PRO_3GEN_129' => [[2064, 2752], [2048, 2732]]
  }.freeze
  class Error < StandardError; end
  class ApiError < Error
    attr_reader :status
    def initialize(status, method, path, body)
      @status = status
      codes = Array(body['errors']).map { |e| e['code'] }.compact.uniq
      super("App Store Connect #{method.upcase} #{path} HTTP #{status} (#{codes.join(', ')})")
    end
  end

  class Client
    def initialize(key_id:, issuer_id:, key_path:)
      @key_id, @issuer_id = key_id, issuer_id
      @private_key = OpenSSL::PKey.read(File.binread(key_path))
      @expires_at = Time.at(0)
    rescue Errno::ENOENT, OpenSSL::PKey::PKeyError
      raise Error, 'App Store Connect credential files could not be loaded'
    end
    def get(path, params = {})
      request('GET', path, params: params)
    end
    def post(path, body)
      request('POST', path, body: body)
    end
    def patch(path, body)
      request('PATCH', path, body: body)
    end
    def all(path, params = {})
      result = get(path, params)
      values = Array(result['data'])
      pages = 1
      while (url = result.dig('links', 'next'))
        raise Error, 'Collection exceeds bounded 20-page read' if pages >= 20
        uri = URI(url)
        raise Error, 'Untrusted API pagination origin' unless uri.scheme == 'https' && uri.host == 'api.appstoreconnect.apple.com'
        result = get(uri.request_uri)
        values.concat(Array(result['data']))
        pages += 1
      end
      values
    end
    private
    def request(method, path, params: {}, body: nil)
      raise Error, 'Expected an API version path' unless path.start_with?('/v1/', '/v2/', '/v3/')
      uri = URI("#{API_ORIGIN}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?
      klass = { 'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post, 'PATCH' => Net::HTTP::Patch }.fetch(method)
      req = klass.new(uri)
      req['Authorization'] = "Bearer #{token}"
      req['Accept'] = 'application/json'
      unless body.nil?
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate(body)
      end
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 60) { |http| http.request(req) }
      parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
      raise ApiError.new(response.code.to_i, method, uri.path, parsed) unless response.code.to_i.between?(200, 299)
      parsed
    rescue JSON::ParserError
      raise Error, 'App Store Connect returned malformed JSON'
    end
    def token
      return @token if Time.now < @expires_at - 60
      now = Time.now.to_i
      header = { alg: 'ES256', kid: @key_id, typ: 'JWT' }
      claims = { iss: @issuer_id, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' }
      encode = ->(value) { Base64.urlsafe_encode64(value, padding: false) }
      input = "#{encode.call(JSON.generate(header))}.#{encode.call(JSON.generate(claims))}"
      der = @private_key.sign(OpenSSL::Digest::SHA256.new, input)
      raw = OpenSSL::ASN1.decode(der).value.map do |part|
        hex = part.value.to_i.to_s(16).rjust(64, '0')
        raise Error, 'Invalid ES256 signature component' if hex.length > 64
        [hex].pack('H*')
      end.join
      @expires_at = Time.at(now + 1200)
      @token = "#{input}.#{encode.call(raw)}"
    end
  end

  def self.verify_identity!(client)
    app = client.get("/v1/apps/#{APP_ID}").fetch('data')
    raise Error, 'Unexpected app bundle ID' unless app.dig('attributes', 'bundleId') == BUNDLE_ID
    ids = client.all('/v1/bundleIds', 'filter[identifier]' => BUNDLE_ID, 'limit' => '200')
    ids.select! { |id| id.dig('attributes', 'identifier') == BUNDLE_ID }
    raise Error, 'Expected Kitta signing team not verified' unless ids.one? && ids.first.dig('attributes', 'seedId') == TEAM_ID
    app
  end

  # Explicit first-release settings only; no privacy publication, listing copy,
  # contact changes, build attachment or submission occurs in this mode.
  class ReadinessRunner
    AGE_BOOLEAN_FIELDS = %w[advertising gambling healthOrWellnessTopics lootBox messagingAndChat parentalControls ageAssurance socialMedia socialMediaAgeRestricted unrestrictedWebAccess userGeneratedContent].freeze
    AGE_FREQUENCY_FIELDS = %w[alcoholTobaccoOrDrugUseOrReferences contests gamblingSimulated gunsOrOtherWeapons medicalOrTreatmentInformation profanityOrCrudeHumor sexualContentGraphicAndNudity sexualContentOrNudity horrorOrFearThemes matureOrSuggestiveThemes violenceCartoonOrFantasy violenceRealisticProlongedGraphicOrSadistic violenceRealistic].freeze
    AGE_MILD_FIELDS = %w[alcoholTobaccoOrDrugUseOrReferences gunsOrOtherWeapons profanityOrCrudeHumor].freeze
    def initialize(client:, apply: false, out: $stdout)
      @client, @apply, @out = client, apply, out
    end
    def run
      app = UniboardAppStoreRelease.verify_identity!(@client)
      versions = @client.all("/v1/apps/#{APP_ID}/appStoreVersions", 'filter[platform]' => 'IOS', 'limit' => '200')
      raise Error, 'Readiness mode is scoped to the initial editable release' unless versions.one? && EDITABLE.include?(versions.first.dig('attributes', 'appStoreState'))
      infos = @client.all("/v1/apps/#{APP_ID}/appInfos", 'limit' => '200').select { |i| EDITABLE.include?(i.dig('attributes', 'appStoreState')) }
      raise Error, 'Editable App Info is absent or ambiguous' unless infos.one?
      info = infos.first
      age = @client.get("/v1/appInfos/#{info['id']}/ageRatingDeclaration").fetch('data')
      raise Error, 'Age-rating declaration is absent' unless age
      categories = %w[UTILITIES REFERENCE].to_h do |id|
        category = @client.get("/v1/appCategories/#{id}").fetch('data')
        raise Error, 'Unexpected category ID' unless category['id'] == id
        [id, category]
      end
      price_points = @client.all("/v1/apps/#{APP_ID}/appPricePoints", 'filter[territory]' => 'USA', 'limit' => '200')
      free = price_points.select { |p| p.dig('attributes', 'customerPrice').to_s.match?(/\A0(?:\.0+)?\z/) }
      raise Error, 'Exact USA free price point is absent or ambiguous' unless free.one?
      price = safe_get("/v1/appPriceSchedules/#{APP_ID}/manualPrices", 'include' => 'appPricePoint', 'limit' => '200')
      check_existing_free_price!(price) if price && Array(price['data']).any?
      territories = @client.all('/v1/territories', 'limit' => '200')
      territory_ids = territories.map { |t| t['id'] }.sort
      raise Error, 'Territory list is empty or ambiguous' if territory_ids.empty? || territory_ids.uniq != territory_ids
      availability = safe_get("/v1/apps/#{APP_ID}/appAvailabilityV2")
      if availability && availability['data']
        current = @client.all("/v2/appAvailabilities/#{availability['data']['id']}/territoryAvailabilities", 'include' => 'territory', 'limit' => '200')
        current_ids = current.select { |t| t.dig('attributes', 'available') == true }.map { |t| t.dig('relationships', 'territory', 'data', 'id') }.sort
        unless current_ids == territory_ids && availability.dig('data', 'attributes', 'availableInNewTerritories') == true
          raise Error, 'Existing availability restrictions need a separate reviewed update'
        end
      end
      @out.puts("#{@apply ? 'APPLY' : 'PLAN'} initial release readiness: licensed Unicode content; occasional technical Unicode references; Utilities/Reference; free USA base price; #{territory_ids.length} territories and future territories")
      writes = []
      if app.dig('attributes', 'contentRightsDeclaration') != 'USES_THIRD_PARTY_CONTENT'
        writes << ['PATCH', "/v1/apps/#{APP_ID}", { 'data' => { 'type' => 'apps', 'id' => APP_ID, 'attributes' => { 'contentRightsDeclaration' => 'USES_THIRD_PARTY_CONTENT' } } }]
      end
      age_answers = AGE_BOOLEAN_FIELDS.to_h { |key| [key, false] }.merge(AGE_FREQUENCY_FIELDS.to_h { |key| [key, 'NONE'] }).merge(AGE_MILD_FIELDS.to_h { |key| [key, 'INFREQUENT_OR_MILD'] }).merge('ageRatingOverrideV2' => 'NONE', 'koreaAgeRatingOverride' => 'NONE')
      unless age_answers.all? { |key, value| age.dig('attributes', key) == value }
        writes << ['PATCH', "/v1/ageRatingDeclarations/#{age['id']}", { 'data' => { 'type' => 'ageRatingDeclarations', 'id' => age['id'], 'attributes' => age_answers } }]
      end
      writes << ['PATCH', "/v1/appInfos/#{info['id']}", { 'data' => { 'type' => 'appInfos', 'id' => info['id'], 'relationships' => { 'primaryCategory' => ref('appCategories', categories['UTILITIES']['id']), 'secondaryCategory' => ref('appCategories', categories['REFERENCE']['id']) } } }]
      if !price || Array(price['data']).empty?
        local_id = '${uniboard-free-price}'
        writes << ['POST', '/v1/appPriceSchedules', {
          'data' => { 'type' => 'appPriceSchedules', 'relationships' => { 'app' => ref('apps', APP_ID), 'baseTerritory' => ref('territories', 'USA'), 'manualPrices' => { 'data' => [{ 'type' => 'appPrices', 'id' => local_id }] } } },
          'included' => [{ 'type' => 'appPrices', 'id' => local_id, 'attributes' => { 'startDate' => nil, 'endDate' => nil }, 'relationships' => { 'appPricePoint' => ref('appPricePoints', free.first['id']) } }]
        }]
      end
      unless availability && availability['data']
        included = territory_ids.map do |id|
          { 'type' => 'territoryAvailabilities', 'id' => "${uniboard-#{id}}", 'attributes' => { 'available' => true, 'preOrderEnabled' => false }, 'relationships' => { 'territory' => ref('territories', id) } }
        end
        writes << ['POST', '/v2/appAvailabilities', {
          'data' => { 'type' => 'appAvailabilities', 'attributes' => { 'availableInNewTerritories' => true }, 'relationships' => { 'app' => ref('apps', APP_ID), 'territoryAvailabilities' => { 'data' => included.map { |t| t.slice('type', 'id') } } } }, 'included' => included
        }]
      end
      writes.each do |method, path, body|
        @out.puts("#{@apply ? method : 'PLAN'} #{path}")
        next unless @apply
        method == 'PATCH' ? @client.patch(path, body) : @client.post(path, body)
      end
      if @apply
        verify_changes!(info['id'], age['id'], age_answers, territory_ids)
        @out.puts('Readiness settings verified; App Privacy and review submission remain separate')
      end
    end
    private
    def verify_changes!(info_id, age_id, answers, territories)
      app = @client.get("/v1/apps/#{APP_ID}").fetch('data')
      raise Error, 'Content rights readback differs' unless app.dig('attributes', 'contentRightsDeclaration') == 'USES_THIRD_PARTY_CONTENT'
      age = @client.get("/v1/appInfos/#{info_id}/ageRatingDeclaration").fetch('data')
      raise Error, 'Age rating declaration ID differs' unless age['id'] == age_id
      raise Error, 'Age questionnaire readback differs' unless answers.all? { |key, value| age.dig('attributes', key) == value }
      { 'primaryCategory' => 'UTILITIES', 'secondaryCategory' => 'REFERENCE' }.each do |relationship, id|
        actual = @client.get("/v1/appInfos/#{info_id}/#{relationship}")['data']
        raise Error, 'Category readback differs' unless actual && actual['id'] == id
      end
      price = @client.get("/v1/appPriceSchedules/#{APP_ID}/manualPrices", 'include' => 'appPricePoint', 'limit' => '200')
      raise Error, 'Free pricing readback is empty' if Array(price['data']).empty?
      check_existing_free_price!(price)
      availability = @client.get("/v1/apps/#{APP_ID}/appAvailabilityV2").fetch('data')
      raise Error, 'Future territory availability readback differs' unless availability.dig('attributes', 'availableInNewTerritories') == true
      current = @client.all("/v2/appAvailabilities/#{availability['id']}/territoryAvailabilities", 'include' => 'territory', 'limit' => '200')
      enabled = current.select { |t| t.dig('attributes', 'available') == true }.map { |t| t.dig('relationships', 'territory', 'data', 'id') }.sort
      raise Error, 'Worldwide availability readback differs' unless enabled == territories
    end
    def safe_get(path, params = {})
      @client.get(path, params)
    rescue ApiError => error
      raise unless error.status == 404
      nil
    end
    def check_existing_free_price!(response)
      raise Error, 'Existing pricing requires a separately bounded review' if response.dig('links', 'next')
      points = Array(response['included']).select { |p| p['type'] == 'appPricePoints' }.to_h { |p| [p['id'], p] }
      Array(response['data']).each do |price|
        id = price.dig('relationships', 'appPricePoint', 'data', 'id')
        raise Error, 'Existing paid or scheduled price requires a separate reviewed update' unless points.dig(id, 'attributes', 'customerPrice').to_s.match?(/\A0(?:\.0+)?\z/)
      end
    end
    def ref(type, id)
      { 'data' => { 'type' => type, 'id' => id } }
    end
  end

  class Runner
    attr_reader :build_id, :version_id
    def initialize(client:, options:, out: $stdout)
      @client, @o, @out = client, options, out
      @apply = !!@o[:apply]
      @submit = !!@o[:submit]
      validate_options!
    end
    def run
      @metadata = read_metadata
      @screenshots = read_screenshots
      verify_app!
      verify_build!
      @version = select_version!
      @version_id = @version.fetch('id')
      @notes = File.read(@o.fetch(:review_notes), encoding: 'UTF-8').strip
      raise Error, 'Review notes must contain instructions within 4,000 UTF-8 bytes' if @notes.empty? || @notes.bytesize > 4000
      log("#{@apply ? 'APPLY' : 'DRY RUN'} #{BUNDLE_ID} #{@o[:version]} (#{@o[:build_number]}), exact build #{@build_id}, source #{@o[:source_commit]}")
      if SUBMITTED.include?(version_state(@version))
        verify_already_submitted!
        return
      end
      @app_info = select_app_info!
      sync_version!
      sync_categories!
      sync_metadata!
      sync_review_detail!
      sync_screenshots!
      verify_prepared! if @apply
      submit! if @submit
      log(@apply ? 'Prepared listing verified' : 'Dry run complete; no external state changed')
    end
    private
    def validate_options!
      %i[version build_number source_commit ci_build_run_id metadata review_notes support_url privacy_url copyright].each do |key|
        raise Error, "Missing --#{key.to_s.tr('_', '-')}" if @o[key].to_s.empty?
      end
      raise Error, 'Version must match the binary marketing version' unless @o[:version].match?(/\A\d+\.\d+(?:\.\d+)?\z/)
      raise Error, 'Build number must be numeric' unless @o[:build_number].match?(/\A\d+\z/)
      raise Error, 'Full source SHA required' unless @o[:source_commit].match?(/\A[0-9a-f]{40}\z/)
      raise Error, 'Cloud run UUID required' unless @o[:ci_build_run_id].match?(/\A[0-9a-fA-F-]{36}\z/)
      %i[support_url privacy_url marketing_url].each do |key|
        next if @o[key].to_s.empty?
        uri = URI(@o[key])
        raise Error, "#{key} must be a public HTTPS URL" unless uri.scheme == 'https' && uri.host && !uri.userinfo
      end
      if @submit
        raise Error, '--submit requires --apply' unless @apply
        raise Error, '--submit requires --privacy-published after App Privacy readback' unless @o[:privacy_published]
        raise Error, '--submit requires --screenshots-manifest' unless @o[:screenshots]
      end
      raise Error, 'Asset wait must be between 1 and 600 seconds' unless @o.fetch(:asset_wait, 180).between?(1, 600)
    end
    def read_metadata
      dirs = Dir.children(@o[:metadata]).select { |name| File.directory?(File.join(@o[:metadata], name)) }.sort
      raise Error, 'Primary en-US metadata is required' unless dirs.include?('en-US')
      raise Error, 'Only en-US and ja metadata are currently supported' unless (dirs - %w[en-US ja]).empty?
      dirs.to_h do |locale|
        attributes = FILES.to_h do |key, (file, limit)|
          value = File.read(File.join(@o[:metadata], locale, file), encoding: 'UTF-8').strip
          raise Error, "#{locale}/#{file} is empty" if value.empty?
          count = key == 'keywords' ? value.bytesize : value.length
          raise Error, "#{locale}/#{file} exceeds #{limit}" if count > limit
          [key, value]
        end
        [locale, attributes]
      end
    end
    def read_screenshots
      return [] unless @o[:screenshots]
      entries = JSON.parse(File.read(@o[:screenshots]))
      raise Error, 'Screenshots manifest must be an array' unless entries.is_a?(Array)
      directory = File.dirname(File.expand_path(@o[:screenshots]))
      seen = []
      entries.map do |entry|
        locale, display = entry.values_at('locale', 'displayType')
        raise Error, 'Screenshot locale has no metadata' unless @metadata.key?(locale)
        raise Error, 'Unsupported screenshot display type' unless PNG_SIZES.key?(display)
        raise Error, 'Duplicate screenshot set in manifest' if seen.include?([locale, display])
        seen << [locale, display]
        files = Array(entry['files'])
        raise Error, 'Each screenshot set must have 1 to 10 assets' unless files.length.between?(1, 10)
        assets = files.map do |path|
          full = File.expand_path(path, directory)
          data = File.binread(full)
          raise Error, 'Only PNG screenshots are supported' unless data.byteslice(0, 8) == "\x89PNG\r\n\x1a\n".b
          raise Error, 'Malformed PNG header' unless data.byteslice(12, 4) == 'IHDR'
          width, height, depth, color = data.byteslice(16, 10).unpack('NNC2')
          sizes = PNG_SIZES.fetch(display)
          raise Error, "Screenshot dimensions do not match #{display}" unless sizes.include?([width, height]) || sizes.include?([height, width])
          raise Error, 'PNG screenshots must have no alpha channel' unless [0, 2].include?(color)
          raise Error, 'Only 8-bit PNG screenshots are supported' unless depth == 8
          check_png_chunks!(data)
          { path: full, fileName: File.basename(full), fileSize: data.bytesize, checksum: Digest::MD5.hexdigest(data) }
        end
        raise Error, 'Duplicate screenshot filenames' unless assets.map { |a| a[:fileName] }.uniq.length == assets.length
        { locale: locale, displayType: display, assets: assets }
      end
    end
    def check_png_chunks!(data)
      offset = 8
      found_end = false
      while offset + 12 <= data.bytesize
        length = data.byteslice(offset, 4).unpack1('N')
        kind = data.byteslice(offset + 4, 4)
        raise Error, 'Malformed PNG chunk' if offset + length + 12 > data.bytesize
        raise Error, 'PNG screenshots must have no transparency' if kind == 'tRNS'
        offset += length + 12
        if kind == 'IEND'
          found_end = true
          break
        end
      end
      raise Error, 'PNG screenshot has no final chunk' unless found_end && offset == data.bytesize
    end
    def verify_app!
      UniboardAppStoreRelease.verify_identity!(@client)
    end
    def verify_build!
      run = @client.get("/v1/ciBuildRuns/#{@o[:ci_build_run_id]}").fetch('data')
      raise Error, 'Cloud run source commit differs' unless run.dig('attributes', 'sourceCommit', 'commitSha') == @o[:source_commit]
      actions = @client.all("/v1/ciBuildRuns/#{run['id']}/actions", 'limit' => '200')
      archives = actions.select { |a| a.dig('attributes', 'actionType') == 'ARCHIVE' }
      raise Error, 'Cloud signed Archive did not succeed' unless archives.one? && archives.first.dig('attributes', 'completionStatus') == 'SUCCEEDED'
      runs = @client.all("/v1/ciProducts/#{PRODUCT_ID}/buildRuns", 'limit' => '200')
      raise Error, 'Cloud run belongs to a different product' unless runs.any? { |r| r['id'] == run['id'] }
      # Cloud can return resource linkage only. Select from authoritative build
      # attributes, never from missing or stale relationship attributes.
      builds = @client.all("/v1/ciBuildRuns/#{run['id']}/builds", 'limit' => '200').map do |link|
        unless link.is_a?(Hash) && link['id'].is_a?(String) && link['id'].match?(/\A[A-Za-z0-9_-]+\z/)
          raise Error, 'Cloud build linkage has a malformed identifier'
        end
        raise Error, 'Cloud build linkage has an unexpected type' if link.key?('type') && link['type'] != 'builds'
        response = @client.get("/v1/builds/#{link['id']}")
        build = response.is_a?(Hash) ? response['data'] : nil
        raise Error, 'Hydrated Cloud build identity differs' unless build.is_a?(Hash) && build['id'] == link['id']
        raise Error, 'Hydrated Cloud build has an unexpected type' if build.key?('type') && build['type'] != 'builds'
        raise Error, 'Hydrated Cloud build attributes are absent' unless build['attributes'].is_a?(Hash)
        build
      end
      matches = builds.select { |b| b.dig('attributes', 'version') == @o[:build_number] }
      raise Error, 'Exact Cloud build is absent or ambiguous' unless matches.one?
      build = matches.first
      @build_id = build.fetch('id')
      a = build.fetch('attributes')
      raise Error, 'Build is not VALID and App Store eligible' unless a['processingState'] == 'VALID' && a['buildAudienceType'] == 'APP_STORE_ELIGIBLE' && a['expired'] == false
      raise Error, 'Export compliance has not been answered' unless a['usesNonExemptEncryption'] == false
      app = @client.get("/v1/builds/#{@build_id}/app").fetch('data')
      raise Error, 'Build belongs to another app' unless app['id'] == APP_ID
      train = @client.get("/v1/builds/#{@build_id}/preReleaseVersion").fetch('data')
      raise Error, 'Build version/platform differs' unless train.dig('attributes', 'version') == @o[:version] && train.dig('attributes', 'platform') == 'IOS'
    end
    def select_version!
      versions = @client.all("/v1/apps/#{APP_ID}/appStoreVersions", 'filter[platform]' => 'IOS', 'include' => 'build', 'limit' => '200')
      @initial_release = versions.none? { |v| SUBMITTED.include?(version_state(v)) }
      if @o[:version_id]
        chosen = versions.find { |v| v['id'] == @o[:version_id] }
      else
        matches = versions.select { |v| v.dig('attributes', 'versionString') == @o[:version] }
        chosen = matches.one? ? matches.first : nil
        # Apple's automatically created empty first version may be renamed.
        chosen ||= versions.first if versions.one? && versions.first.dig('attributes', 'appStoreState') == 'PREPARE_FOR_SUBMISSION' && versions.first.dig('relationships', 'build', 'data').nil?
      end
      raise Error, 'Select an existing exact/initial version with --version-id' unless chosen
      state = version_state(chosen)
      raise Error, "Version is not editable/submitted: #{state}" unless (EDITABLE + SUBMITTED).include?(state)
      chosen
    end
    def select_app_info!
      infos = @client.all("/v1/apps/#{APP_ID}/appInfos", 'limit' => '200')
      choices = infos.select { |i| EDITABLE.include?(i.dig('attributes', 'appStoreState')) }
      raise Error, 'Editable App Info is absent/ambiguous' unless choices.one?
      choices.first
    end
    def sync_version!
      change('PATCH', "/v1/appStoreVersions/#{@version_id}", 'appStoreVersions',
             { versionString: @o[:version], copyright: @o[:copyright], reviewType: 'APP_STORE' },
             id: @version_id, relationships: { build: ref('builds', @build_id) }, label: 'version and exact build')
    end
    def sync_metadata!
      info_locs = localization_index!(@client.all("/v1/appInfos/#{@app_info['id']}/appInfoLocalizations", 'limit' => '200'), 'App Info')
      version_locs = read_version_localizations!
      @version_localizations = version_locs
      @metadata.each do |locale, a|
        info_attrs = a.slice('name', 'subtitle').merge('privacyPolicyUrl' => @o[:privacy_url])
        new_info = info_locs[locale].nil?
        updated_info = sync_localization(info_locs[locale], 'appInfoLocalizations', info_attrs, 'appInfo', @app_info['id'], locale)
        if @apply && new_info
          # Creating App Info can also create this locale on the App Store version.
          # Refresh before deciding whether its metadata needs PATCH or POST.
          info_locs[locale] = updated_info
          version_locs = read_version_localizations!
          @version_localizations = version_locs
        end
        version_attrs = a.slice('description', 'keywords', 'promotionalText', 'whatsNew').merge('supportUrl' => @o[:support_url])
        version_attrs.delete('whatsNew') if @initial_release
        version_attrs['marketingUrl'] = @o[:marketing_url] if @o[:marketing_url]
        updated = sync_localization(version_locs[locale], 'appStoreVersionLocalizations', version_attrs, 'appStoreVersion', @version_id, locale)
        @version_localizations[locale] = updated if updated
      end
    end
    def localization_index!(records, label)
      records.each_with_object({}) do |record, indexed|
        locale = record.dig('attributes', 'locale')
        raise Error, "#{label} localization has missing identity/locale" if record['id'].to_s.empty? || !locale.is_a?(String) || locale.empty?
        raise Error, "#{label} has ambiguous duplicate locale: #{locale}" if indexed.key?(locale)
        indexed[locale] = record
      end
    end
    def read_version_localizations!
      indexed = localization_index!(@client.all("/v1/appStoreVersions/#{@version_id}/appStoreVersionLocalizations", 'limit' => '200'), 'App Store version')
      extras = indexed.keys - @metadata.keys
      raise Error, "Existing locale metadata absent from source: #{extras.join(', ')}" unless extras.empty?
      indexed
    end
    def sync_categories!
      categories = { 'primaryCategory' => 'UTILITIES', 'secondaryCategory' => 'REFERENCE' }
      categories.each_value do |id|
        category = @client.get("/v1/appCategories/#{id}").fetch('data')
        raise Error, 'Unexpected category ID' unless category['id'] == id
      end
      change('PATCH', "/v1/appInfos/#{@app_info['id']}", 'appInfos', {}, id: @app_info['id'],
             relationships: categories.transform_values { |id| ref('appCategories', id) }, label: 'Utilities and Reference categories')
    end
    def sync_localization(existing, type, attrs, parent_type, parent_id, locale)
      if existing
        change('PATCH', "/v1/#{type}/#{existing['id']}", type, attrs, id: existing['id'], label: "#{locale} #{type}")
        existing
      else
        change('POST', "/v1/#{type}", type, attrs.merge('locale' => locale), relationships: { parent_type => ref(parent_type == 'appInfo' ? 'appInfos' : 'appStoreVersions', parent_id) }, label: "#{locale} #{type}")&.fetch('data')
      end
    end
    def sync_review_detail!
      existing = @client.get("/v1/appStoreVersions/#{@version_id}/appStoreReviewDetail")['data']
      desired = { 'notes' => @notes, 'demoAccountRequired' => false }
      current = existing ? existing.fetch('attributes') : {}
      missing = CONTACT_KEYS.select { |k| current[k].to_s.strip.empty? }
      if missing.any?
        raise Error, 'Missing review contact; explicit --reuse-beta-review-contact required' unless @o[:reuse_contact]
        approved = @client.get("/v1/apps/#{APP_ID}/betaAppReviewDetail").fetch('data').fetch('attributes')
        missing.each do |key|
          raise Error, "Approved beta contact field is missing: #{key}" if approved[key].to_s.strip.empty?
          desired[key] = approved[key]
        end
      end
      change(existing ? 'PATCH' : 'POST', existing ? "/v1/appStoreReviewDetails/#{existing['id']}" : '/v1/appStoreReviewDetails',
             'appStoreReviewDetails', desired, id: existing&.fetch('id'),
             relationships: existing ? {} : { appStoreVersion: ref('appStoreVersions', @version_id) }, label: 'review notes and missing approved contacts')
    end
    def sync_screenshots!
      @screenshots.each do |entry|
        localization = @version_localizations[entry[:locale]]
        unless localization
          log("PLAN #{entry[:locale]} #{entry[:displayType]} screenshots after localization creation")
          next
        end
        sets = @client.all("/v1/appStoreVersionLocalizations/#{localization['id']}/appScreenshotSets", 'limit' => '200')
        matches = sets.select { |s| s.dig('attributes', 'screenshotDisplayType') == entry[:displayType] }
        raise Error, 'Duplicate screenshot display sets exist' if matches.length > 1
        set = matches.first
        set ||= change('POST', '/v1/appScreenshotSets', 'appScreenshotSets', { screenshotDisplayType: entry[:displayType] },
                       relationships: { appStoreVersionLocalization: ref('appStoreVersionLocalizations', localization['id']) }, label: "#{entry[:locale]} #{entry[:displayType]} screenshot set")&.fetch('data')
        next unless set
        screenshots = @client.all("/v1/appScreenshotSets/#{set['id']}/appScreenshots", 'limit' => '200')
        extra_names = screenshots.map { |s| s.dig('attributes', 'fileName') } - entry[:assets].map { |a| a[:fileName] }
        raise Error, 'Existing screenshots differ; replacement requires a separate reviewed action' unless extra_names.empty?
        ordered = entry[:assets].map { |asset| sync_screenshot(set['id'], screenshots, asset) }
        if @apply
          @client.patch("/v1/appScreenshotSets/#{set['id']}/relationships/appScreenshots", 'data' => ordered.map { |id| { 'type' => 'appScreenshots', 'id' => id } })
          actual = @client.all("/v1/appScreenshotSets/#{set['id']}/appScreenshots", 'limit' => '200').map { |s| s['id'] }
          raise Error, 'Screenshot order readback differs' unless actual == ordered
        end
      end
    end
    def sync_screenshot(set_id, existing, asset)
      matches = existing.select { |s| s.dig('attributes', 'fileName') == asset[:fileName] }
      raise Error, 'Ambiguous screenshot filename' if matches.length > 1
      screenshot = matches.first
      if screenshot
        raise Error, 'Existing screenshot checksum differs or upload is incomplete' unless screenshot.dig('attributes', 'sourceFileChecksum') == asset[:checksum]
        wait_for_asset!(screenshot['id'], asset[:checksum]) if @apply
        return screenshot['id']
      end
      screenshot = change('POST', '/v1/appScreenshots', 'appScreenshots', asset.slice(:fileName, :fileSize),
                          relationships: { appScreenshotSet: ref('appScreenshotSets', set_id) }, label: "screenshot #{asset[:fileName]}")&.fetch('data')
      return nil unless screenshot
      ops = screenshot.dig('attributes', 'uploadOperations')
      raise Error, 'Screenshot reservation has no upload instructions' if !ops.is_a?(Array) || ops.empty?
      data = File.binread(asset[:path])
      raise Error, 'Screenshot changed after preflight' unless Digest::MD5.hexdigest(data) == asset[:checksum]
      ops.each { |op| upload_part!(op, data) }
      @client.patch("/v1/appScreenshots/#{screenshot['id']}", 'data' => { 'type' => 'appScreenshots', 'id' => screenshot['id'], 'attributes' => { 'uploaded' => true, 'sourceFileChecksum' => asset[:checksum] } })
      wait_for_asset!(screenshot['id'], asset[:checksum])
      screenshot['id']
    end
    def upload_part!(operation, data)
      uri = URI(operation.fetch('url'))
      raise Error, 'Untrusted upload host' unless uri.scheme == 'https' && uri.host.end_with?('.apple.com') && !uri.userinfo
      raise Error, 'Unsupported asset upload method' unless operation['method'] == 'PUT'
      offset, length = operation.values_at('offset', 'length')
      raise Error, 'Invalid asset byte range' unless offset.is_a?(Integer) && length.is_a?(Integer) && offset >= 0 && length > 0 && offset + length <= data.bytesize
      req = Net::HTTP::Put.new(uri)
      Array(operation['requestHeaders']).each do |h|
        raise Error, 'Unexpected authorization in upload instruction' if h['name'].casecmp('Authorization').zero?
        req[h.fetch('name')] = h.fetch('value')
      end
      req.body = data.byteslice(offset, length)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 90) { |http| http.request(req) }
      raise Error, "Asset upload HTTP #{response.code}" unless response.code.to_i.between?(200, 299)
    rescue URI::InvalidURIError
      raise Error, 'Malformed asset upload URL'
    end
    def wait_for_asset!(id, checksum)
      deadline = Time.now + @o.fetch(:asset_wait, 180)
      loop do
        a = @client.get("/v1/appScreenshots/#{id}").fetch('data').fetch('attributes')
        state = a.dig('assetDeliveryState', 'state')
        if state == 'COMPLETE'
          raise Error, 'Processed screenshot checksum differs' unless a['sourceFileChecksum'] == checksum
          return
        end
        raise Error, 'Screenshot processing failed' if state == 'FAILED'
        raise Error, 'Screenshot is still processing; inspect and re-run after COMPLETE' if Time.now >= deadline
        sleep [15, deadline - Time.now].min
      end
    end
    def verify_prepared!
      v = @client.get("/v1/appStoreVersions/#{@version_id}", 'include' => 'build').fetch('data')
      raise Error, 'Attached build differs' unless v.dig('relationships', 'build', 'data', 'id') == @build_id
      raise Error, 'Listing version differs' unless v.dig('attributes', 'versionString') == @o[:version]
      locals = @client.all("/v1/appStoreVersions/#{@version_id}/appStoreVersionLocalizations", 'limit' => '200').to_h { |l| [l.dig('attributes', 'locale'), l] }
      info_locs = @client.all("/v1/appInfos/#{@app_info['id']}/appInfoLocalizations", 'limit' => '200').to_h { |l| [l.dig('attributes', 'locale'), l] }
      @metadata.each do |locale, expected|
        expected.each do |key, value|
          next if key == 'whatsNew' && @initial_release
          actual = %w[name subtitle].include?(key) ? info_locs.dig(locale, 'attributes', key) : locals.dig(locale, 'attributes', key)
          raise Error, "#{locale} #{key} readback differs" unless actual == value
        end
        raise Error, "#{locale} support URL readback differs" unless locals.dig(locale, 'attributes', 'supportUrl') == @o[:support_url]
        raise Error, "#{locale} privacy URL readback differs" unless info_locs.dig(locale, 'attributes', 'privacyPolicyUrl') == @o[:privacy_url]
      end
      detail = @client.get("/v1/appStoreVersions/#{@version_id}/appStoreReviewDetail").fetch('data').fetch('attributes')
      raise Error, 'Review contact is incomplete' unless CONTACT_KEYS.all? { |key| !detail[key].to_s.strip.empty? }
      raise Error, 'Review notes readback differs' unless detail['notes'] == @notes && detail['demoAccountRequired'] == false
    end
    def submit!
      verify_readiness!
      submissions = @client.all("/v1/apps/#{APP_ID}/reviewSubmissions", 'filter[platform]' => 'IOS', 'limit' => '200').reject { |s| s.dig('attributes', 'state') == 'COMPLETE' }
      raise Error, 'Multiple active submissions require separate review' if submissions.length > 1
      submission = submissions.first
      if submission
        items = @client.all("/v1/reviewSubmissions/#{submission['id']}/items", 'include' => 'appStoreVersion', 'limit' => '200')
        raise Error, 'Active submission contains an unrelated item' if items.any? { |i| i.dig('relationships', 'appStoreVersion', 'data', 'id') != @version_id }
      else
        submission = @client.post('/v1/reviewSubmissions', 'data' => { 'type' => 'reviewSubmissions', 'attributes' => { 'platform' => 'IOS' }, 'relationships' => { 'app' => ref('apps', APP_ID) } }).fetch('data')
        items = []
      end
      if items.empty?
        @client.post('/v1/reviewSubmissionItems', 'data' => { 'type' => 'reviewSubmissionItems', 'relationships' => { 'reviewSubmission' => ref('reviewSubmissions', submission['id']), 'appStoreVersion' => ref('appStoreVersions', @version_id) } })
      elsif items.any? { |i| %w[REJECTED UNRESOLVED_ISSUES].include?(i.dig('attributes', 'state')) }
        raise Error, 'Rejected review item requires a separately reviewed resolution'
      end
      @client.patch("/v1/reviewSubmissions/#{submission['id']}", 'data' => { 'type' => 'reviewSubmissions', 'id' => submission['id'], 'attributes' => { 'submitted' => true } }) unless REVIEW_STATES.include?(submission.dig('attributes', 'state'))
      verify_submission!(submission['id'])
    end
    def verify_readiness!
      app = @client.get("/v1/apps/#{APP_ID}").fetch('data')
      raise Error, 'Content rights declaration is missing' if app.dig('attributes', 'contentRightsDeclaration').nil?
      info = @client.get("/v1/appInfos/#{@app_info['id']}").fetch('data')
      raise Error, 'Age rating questionnaire is incomplete' if info.dig('attributes', 'appStoreAgeRating').nil?
      primary = @client.get("/v1/appInfos/#{@app_info['id']}/primaryCategory")['data']
      raise Error, 'Primary category is not Utilities' unless primary && primary['id'] == 'UTILITIES'
      secondary = @client.get("/v1/appInfos/#{@app_info['id']}/secondaryCategory")['data']
      raise Error, 'Secondary category is not Reference' unless secondary && secondary['id'] == 'REFERENCE'
      price_response = @client.get("/v1/appPriceSchedules/#{APP_ID}/manualPrices", 'include' => 'appPricePoint', 'limit' => '200')
      raise Error, 'Pricing read exceeds page; inspect the schedule separately' if price_response.dig('links', 'next')
      today = Time.now.utc.strftime('%Y-%m-%d')
      prices = Array(price_response['data']).select do |p|
        a = p.fetch('attributes')
        (a['startDate'].nil? || a['startDate'] <= today) && (a['endDate'].nil? || a['endDate'] > today)
      end
      raise Error, 'Current app pricing is absent' if prices.empty?
      points = Array(price_response['included']).select { |p| p['type'] == 'appPricePoints' }.to_h { |p| [p['id'], p] }
      prices.each do |price|
        point_id = price.dig('relationships', 'appPricePoint', 'data', 'id')
        amount = points.dig(point_id, 'attributes', 'customerPrice')
        raise Error, 'Current app price is not verified as free' unless amount.to_s.match?(/\A0(?:\.0+)?\z/)
      end
      availability = @client.get("/v1/apps/#{APP_ID}/appAvailabilityV2")['data']
      raise Error, 'App availability is absent' unless availability
      territories = @client.all("/v2/appAvailabilities/#{availability['id']}/territoryAvailabilities", 'limit' => '200')
      raise Error, 'No App Store territory is enabled' unless territories.any? { |t| t.dig('attributes', 'available') == true }
      @metadata.each_key do |locale|
        entries = @screenshots.select { |e| e[:locale] == locale }
        raise Error, "#{locale} requires iPhone6.9/6.5 screenshots" unless entries.any? { |e| %w[APP_IPHONE_67 APP_IPHONE_65].include?(e[:displayType]) }
        raise Error, "#{locale} requires iPad13-inch screenshots" unless entries.any? { |e| e[:displayType] == 'APP_IPAD_PRO_3GEN_129' }
      end
    end
    def verify_already_submitted!
      raise Error, 'Already submitted listing version differs' unless @version.dig('attributes', 'versionString') == @o[:version]
      raise Error, 'Already submitted version has a different build' unless @version.dig('relationships', 'build', 'data', 'id') == @build_id
      submissions = @client.all("/v1/apps/#{APP_ID}/reviewSubmissions", 'filter[platform]' => 'IOS', 'include' => 'appStoreVersionForReview', 'limit' => '200')
      matches = submissions.select { |s| s.dig('relationships', 'appStoreVersionForReview', 'data', 'id') == @version_id }
      raise Error, 'Cannot resolve exact submitted version' if matches.empty?
      active = matches.reject { |s| s.dig('attributes', 'state') == 'COMPLETE' }
      raise Error, 'Multiple active submissions reference the exact version' if active.length > 1
      candidates = active.empty? ? matches : active
      chosen = candidates.max_by do |s|
        date = s.dig('attributes', 'submittedDate')
        date ? Time.parse(date) : Time.at(0)
      end
      verify_submission!(chosen['id'])
    end
    def verify_submission!(id)
      submission = @client.get("/v1/reviewSubmissions/#{id}", 'include' => 'appStoreVersionForReview').fetch('data')
      state = submission.dig('attributes', 'state')
      raise Error, "Review submission is #{state}" unless REVIEW_STATES.include?(state)
      raise Error, 'Submission version differs' unless submission.dig('relationships', 'appStoreVersionForReview', 'data', 'id') == @version_id
      version = @client.get("/v1/appStoreVersions/#{@version_id}", 'include' => 'build').fetch('data')
      raise Error, 'Submitted build differs' unless version.dig('relationships', 'build', 'data', 'id') == @build_id
      raise Error, "App Store version is not submitted (#{version_state(version)})" unless SUBMITTED.include?(version_state(version))
      items = @client.all("/v1/reviewSubmissions/#{id}/items", 'include' => 'appStoreVersion', 'limit' => '200')
      raise Error, 'Submission does not contain the exact version' unless items.one? && items.first.dig('relationships', 'appStoreVersion', 'data', 'id') == @version_id
      item_state = items.first.dig('attributes', 'state')
      raise Error, "Review item is not in a valid submitted state (#{item_state})" unless VALID_REVIEW_ITEM_STATES.include?(item_state)
      log("App Store submission #{id}: #{state}; version #{version_state(version)}; exact build #{@build_id}")
    end
    def change(method, path, type, attrs, id: nil, relationships: {}, label:)
      log("#{@apply ? method : 'PLAN'} #{label}")
      return nil unless @apply
      data = { 'type' => type }
      data['attributes'] = attrs unless attrs.empty?
      data['id'] = id if id
      data['relationships'] = relationships unless relationships.empty?
      method == 'POST' ? @client.post(path, 'data' => data) : @client.patch(path, 'data' => data)
    end
    def ref(type, id)
      { 'data' => { 'type' => type, 'id' => id } }
    end
    def version_state(v)
      v.dig('attributes', 'appStoreState') || v.dig('attributes', 'appVersionState')
    end
    def log(message)
      @out.puts(message)
    end
  end

  def self.main(argv)
    o = { metadata: File.expand_path('../fastlane/metadata', __dir__), asset_wait: 180 }
    parser = OptionParser.new do |p|
      p.banner = 'Usage: ruby Scripts/app_store_release.rb [options] (GET-only by default)'
      %i[version build_number source_commit ci_build_run_id version_id metadata review_notes support_url privacy_url marketing_url copyright].each do |key|
        p.on("--#{key.to_s.tr('_', '-')} VALUE") { |value| o[key] = value }
      end
      p.on('--screenshots-manifest PATH') { |value| o[:screenshots] = value }
      p.on('--asset-wait-seconds N', Integer) { |value| o[:asset_wait] = value }
      p.on('--reuse-beta-review-contact') { o[:reuse_contact] = true }
      p.on('--privacy-published') { o[:privacy_published] = true }
      p.on('--apply') { o[:apply] = true }
      p.on('--submit') { o[:submit] = true }
      p.on('--readiness') { o[:readiness] = true }
      p.on('--apply-readiness') { o[:readiness] = true; o[:apply_readiness] = true }
      p.on('-h', '--help') { puts p; return 0 }
    end
    parser.parse!(argv)
    raise Error, 'Unexpected positional arguments' unless argv.empty?
    key_id = ENV.fetch('ASC_KEY_ID')
    issuer = ENV['ASC_ISSUER_ID'] || File.read(File.expand_path('~/.appstoreconnect/private_keys/issuer')).strip
    key_path = ENV['ASC_KEY_PATH'] || File.expand_path("~/.appstoreconnect/private_keys/AuthKey_#{key_id}.p8")
    client = Client.new(key_id: key_id, issuer_id: issuer, key_path: key_path)
    if o[:readiness]
      raise Error, 'Readiness mode does not accept --apply or --submit' if o[:apply] || o[:submit]
      ReadinessRunner.new(client: client, apply: !!o[:apply_readiness]).run
    else
      Runner.new(client: client, options: o).run
    end
    0
  rescue Error, OptionParser::ParseError, KeyError, Errno::ENOENT, URI::InvalidURIError => error
    # Do not print raw network errors: upload URLs contain temporary credentials.
    warn "Release stopped: #{error.message}"
    1
  rescue StandardError => error
    warn "Release stopped (#{error.class}); re-query App Store Connect before retrying a write"
    1
  end
end

exit UniboardAppStoreRelease.main(ARGV) if $PROGRAM_NAME == __FILE__
