# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require_relative '../app_store_release'

class AppStoreReleaseTest < Minitest::Test
  M = UniboardAppStoreRelease
  class FakeClient
    attr_reader :writes
    attr_accessor :commit, :team, :processing, :audience, :expired, :archive, :binary_version, :contacts, :price, :territory
    def initialize
      @writes = []
      @commit = 'a' * 40
      @team = M::TEAM_ID
      @processing = 'VALID'
      @audience = 'APP_STORE_ELIGIBLE'
      @expired = false
      @archive = 'SUCCEEDED'
      @binary_version = '1.0.0'
      @contacts = nil
      @price = '0.00'
      @territory = true
    end
    def get(path, _params = {})
      if path == "/v1/appPriceSchedules/#{M::APP_ID}/manualPrices"
        return { 'data' => [{ 'attributes' => { 'startDate' => nil, 'endDate' => nil }, 'relationships' => { 'appPricePoint' => { 'data' => { 'id' => 'price' } } } }],
                 'included' => [{ 'id' => 'price', 'type' => 'appPricePoints', 'attributes' => { 'customerPrice' => @price } }] }
      end
      value = case path
      when "/v1/apps/#{M::APP_ID}", '/v1/builds/build/app'
        { 'id' => M::APP_ID, 'attributes' => { 'bundleId' => M::BUNDLE_ID, 'contentRightsDeclaration' => 'USES_THIRD_PARTY_CONTENT' } }
      when '/v1/ciBuildRuns/11111111-1111-1111-1111-111111111111'
        { 'id' => 'run', 'attributes' => { 'sourceCommit' => { 'commitSha' => @commit } } }
      when '/v1/builds/build'
        { 'id' => 'build', 'type' => 'builds', 'attributes' => { 'version' => '10', 'processingState' => @processing,
          'buildAudienceType' => @audience, 'expired' => @expired, 'usesNonExemptEncryption' => false } }
      when '/v1/builds/build/preReleaseVersion'
        { 'attributes' => { 'version' => @binary_version, 'platform' => 'IOS' } }
      when %r{\A/v1/appCategories/(UTILITIES|REFERENCE)\z}
        { 'id' => path.split('/').last }
      when '/v1/appInfos/info'
        { 'attributes' => { 'appStoreAgeRating' => 'FOUR_PLUS' } }
      when '/v1/appInfos/info/primaryCategory'
        { 'id' => 'UTILITIES' }
      when '/v1/appInfos/info/secondaryCategory'
        { 'id' => 'REFERENCE' }
      when "/v1/apps/#{M::APP_ID}/appAvailabilityV2"
        { 'id' => 'availability' }
      when '/v1/appStoreVersions/version/appStoreReviewDetail'
        @contacts && { 'id' => 'review', 'attributes' => @contacts }
      when "/v1/apps/#{M::APP_ID}/betaAppReviewDetail"
        { 'attributes' => M::CONTACT_KEYS.to_h { |key| [key, "approved-#{key}"] } }
      else
        raise "Unexpected GET #{path}"
      end
      { 'data' => value }
    end
    def all(path, _params = {})
      case path
      when '/v1/bundleIds'
        # Apple identifier filtering also returns the extension prefix match.
        [{ 'attributes' => { 'identifier' => "#{M::BUNDLE_ID}.keyboard", 'seedId' => @team } },
         { 'attributes' => { 'identifier' => M::BUNDLE_ID, 'seedId' => @team } }]
      when '/v1/ciBuildRuns/run/actions'
        [{ 'attributes' => { 'actionType' => 'ARCHIVE', 'completionStatus' => @archive } }]
      when "/v1/ciProducts/#{M::PRODUCT_ID}/buildRuns"
        [{ 'id' => 'run' }]
      when '/v1/ciBuildRuns/run/builds'
        [{ 'id' => 'build', 'attributes' => { 'version' => '10', 'processingState' => @processing,
           'buildAudienceType' => @audience, 'expired' => @expired, 'usesNonExemptEncryption' => false } }]
      when "/v1/apps/#{M::APP_ID}/appStoreVersions"
        [{ 'id' => 'version', 'attributes' => { 'versionString' => '1.0', 'appStoreState' => 'PREPARE_FOR_SUBMISSION' },
           'relationships' => { 'build' => { 'data' => nil } } }]
      when "/v1/apps/#{M::APP_ID}/appInfos"
        [{ 'id' => 'info', 'attributes' => { 'appStoreState' => 'PREPARE_FOR_SUBMISSION' } }]
      when '/v1/appInfos/info/appInfoLocalizations', '/v1/appStoreVersions/version/appStoreVersionLocalizations'
        [{ 'id' => 'localization', 'attributes' => { 'locale' => 'en-US' } }]
      when '/v2/appAvailabilities/availability/territoryAvailabilities'
        [{ 'attributes' => { 'available' => @territory } }]
      else
        raise "Unexpected collection #{path}"
      end
    end
    def post(path, body)
      @writes << ['POST', path, body]
      { 'data' => { 'id' => 'created', 'attributes' => body.dig('data', 'attributes') } }
    end
    def patch(path, body)
      @writes << ['PATCH', path, body]
      { 'data' => { 'id' => body.dig('data', 'id'), 'attributes' => body.dig('data', 'attributes') } }
    end
  end
  class BuildLinkageClient < FakeClient
    attr_accessor :linkages, :records
    attr_reader :hydrated_ids
    def initialize
      super
      @linkages = [{ 'id' => 'build', 'type' => 'builds' }]
      @records = {}
      @hydrated_ids = []
    end
    def all(path, params = {})
      return @linkages if path == '/v1/ciBuildRuns/run/builds'
      super
    end
    def get(path, params = {})
      if (match = path.match(%r{\A/v1/builds/([^/]+)\z}))
        id = match[1]
        @hydrated_ids << id
        return { 'data' => @records[id] } if @records.key?(id)
      end
      super
    end
  end
  class ReadinessClient < FakeClient
    attr_reader :age_answers
    attr_accessor :restricted
    def initialize
      super
      @rights = nil
      @age_answers = {}
      @categories = {}
      @price_present = false
      @availability_present = false
      @restricted = false
    end
    def get(path, params = {})
      case path
      when "/v1/apps/#{M::APP_ID}"
        response = super
        response['data']['attributes']['contentRightsDeclaration'] = @rights
        response
      when '/v1/appInfos/info/ageRatingDeclaration'
        { 'data' => { 'id' => 'age', 'attributes' => @age_answers } }
      when '/v1/appInfos/info/primaryCategory', '/v1/appInfos/info/secondaryCategory'
        { 'data' => @categories[path.split('/').last] }
      when "/v1/appPriceSchedules/#{M::APP_ID}/manualPrices"
        raise M::ApiError.new(404, 'GET', path, {}) unless @price_present
        super
      when "/v1/apps/#{M::APP_ID}/appAvailabilityV2"
        raise M::ApiError.new(404, 'GET', path, {}) unless @availability_present
        { 'data' => { 'id' => 'availability', 'attributes' => { 'availableInNewTerritories' => true } } }
      else
        super
      end
    end
    def all(path, params = {})
      case path
      when "/v1/apps/#{M::APP_ID}/appPricePoints"
        [{ 'id' => 'usa-free', 'attributes' => { 'customerPrice' => '0.00' } }]
      when '/v1/territories'
        %w[JPN USA].map { |id| { 'id' => id } }
      when '/v2/appAvailabilities/availability/territoryAvailabilities'
        %w[JPN USA].map { |id| { 'attributes' => { 'available' => !(id == 'JPN' && @restricted) }, 'relationships' => { 'territory' => { 'data' => { 'id' => id } } } } }
      else
        super
      end
    end
    def patch(path, body)
      case path
      when "/v1/apps/#{M::APP_ID}"
        @rights = body.dig('data', 'attributes', 'contentRightsDeclaration')
      when '/v1/ageRatingDeclarations/age'
        @age_answers = body.dig('data', 'attributes')
      when '/v1/appInfos/info'
        @categories = body.dig('data', 'relationships').transform_values { |r| r['data'] }
      end
      super
    end
    def post(path, body)
      @price_present = true if path == '/v1/appPriceSchedules'
      @availability_present = true if path == '/v2/appAvailabilities'
      super
    end
    def paid_price!
      @price_present = true
      @price = '1.99'
    end
    def restricted_availability!
      @availability_present = true
      @restricted = true
    end
  end
  class ReviewClient < FakeClient
    attr_accessor :item_state, :version_state, :submissions
    attr_reader :read_submission_ids
    def initialize
      super
      @item_state = 'READY_FOR_REVIEW'
      @version_state = 'WAITING_FOR_REVIEW'
      @submissions = [{ 'id' => 'active', 'attributes' => { 'state' => 'WAITING_FOR_REVIEW', 'submittedDate' => '2026-10-03T10:00:00Z' },
                        'relationships' => { 'appStoreVersionForReview' => { 'data' => { 'id' => 'version' } } } }]
      @read_submission_ids = []
    end
    def get(path, params = {})
      if path == '/v1/appStoreVersions/version'
        return { 'data' => { 'id' => 'version', 'attributes' => { 'versionString' => '1.0.0', 'appStoreState' => @version_state },
                            'relationships' => { 'build' => { 'data' => { 'id' => 'build' } } } } }
      end
      if path.start_with?('/v1/reviewSubmissions/')
        id = path.split('/').last
        @read_submission_ids << id
        return { 'data' => @submissions.find { |s| s['id'] == id } }
      end
      super
    end
    def all(path, params = {})
      return @submissions if path == "/v1/apps/#{M::APP_ID}/reviewSubmissions"
      if path.start_with?('/v1/reviewSubmissions/')
        id = path.split('/')[-2]
        return [{ 'attributes' => { 'state' => id == 'old' ? 'REMOVED' : @item_state },
                  'relationships' => { 'appStoreVersion' => { 'data' => { 'id' => 'version' } } } }]
      end
      super
    end
  end
  class AutomaticLocaleClient < FakeClient
    attr_accessor :duplicate_infos, :duplicate_versions
    def initialize
      super
      @created_ja = false
    end
    def all(path, params = {})
      if path == '/v1/appInfos/info/appInfoLocalizations'
        records = [{ 'id' => 'info-en-US', 'attributes' => { 'locale' => 'en-US' } }]
        records << { 'id' => 'info-ja', 'attributes' => { 'locale' => 'ja' } } if @created_ja
        records << { 'id' => 'info-duplicate', 'attributes' => { 'locale' => 'en-US' } } if @duplicate_infos
        return records
      end
      if path == '/v1/appStoreVersions/version/appStoreVersionLocalizations'
        records = [{ 'id' => 'version-en-US', 'attributes' => { 'locale' => 'en-US' } }]
        records << { 'id' => 'version-ja', 'attributes' => { 'locale' => 'ja' } } if @created_ja
        records << { 'id' => 'version-duplicate', 'attributes' => { 'locale' => 'en-US' } } if @duplicate_versions
        return records
      end
      super
    end
    def post(path, body)
      locale = body.dig('data', 'attributes', 'locale')
      if path == '/v1/appStoreVersionLocalizations' && locale == 'ja' && @created_ja
        raise M::ApiError.new(409, 'POST', path, 'errors' => [{ 'code' => 'ENTITY_ERROR.ATTRIBUTE.DUPLICATE' }])
      end
      # Mirrors the observed ASC side effect of a new App Info locale.
      @created_ja = true if path == '/v1/appInfoLocalizations' && locale == 'ja'
      super
    end
  end

  def setup
    @tmp = Dir.mktmpdir('uniboard-release-test')
    %w[en-US ja].each do |locale|
      path = File.join(@tmp, 'metadata', locale)
      FileUtils.mkdir_p(path)
      M::FILES.each_value { |file, _| File.write(File.join(path, file), "Valid listing copy\n") }
    end
    @notes = File.join(@tmp, 'review.txt')
    File.write(@notes, 'Enable the keyboard in Settings. No account or Full Access required.')
    @client = FakeClient.new
    @out = StringIO.new
  end
  def teardown
    FileUtils.remove_entry(@tmp)
  end
  def options
    { version: '1.0.0', build_number: '10', source_commit: 'a' * 40,
      ci_build_run_id: '11111111-1111-1111-1111-111111111111',
      metadata: File.join(@tmp, 'metadata'), review_notes: @notes,
      support_url: 'https://example.com/support', privacy_url: 'https://example.com/privacy',
      copyright: '2026 Kitta Ltd', reuse_contact: true }
  end
  def runner(overrides = {})
    M::Runner.new(client: @client, options: options.merge(overrides), out: @out)
  end
  def test_complete_dry_run_makes_no_writes_and_verifies_exact_team_after_prefix_filter
    instance = runner
    instance.run
    assert_empty @client.writes
    assert_equal 'build', instance.build_id
    assert_equal 'version', instance.version_id
    assert_includes @out.string, 'Dry run complete'
    refute_includes @out.string, 'approved-contactEmail'
  end
  def test_bare_cloud_linkage_is_hydrated_before_selecting_exact_build
    @client = BuildLinkageClient.new
    @client.linkages.unshift({ 'id' => 'previous', 'type' => 'builds' })
    previous = FakeClient.new.get('/v1/builds/build').fetch('data')
    previous['id'] = 'previous'
    previous['attributes']['version'] = '9'
    @client.records['previous'] = previous
    instance = runner
    instance.run
    assert_equal %w[previous build], @client.hydrated_ids
    assert_equal 'build', instance.build_id
    assert_empty @client.writes
    assert_includes @out.string, 'Dry run complete'
  end
  def test_relationship_attributes_cannot_override_hydrated_build_version
    @client = BuildLinkageClient.new
    @client.linkages = [FakeClient.new.all('/v1/ciBuildRuns/run/builds').first]
    record = FakeClient.new.get('/v1/builds/build').fetch('data')
    record['attributes']['version'] = '11'
    @client.records['build'] = record
    error = assert_raises(M::Error) { runner(apply: true).run }
    assert_equal 'Exact Cloud build is absent or ambiguous', error.message
    assert_equal ['build'], @client.hydrated_ids
    assert_empty @client.writes
  end
  def test_malformed_linkage_identity_fails_before_fetch_or_write
    [nil, {}, { 'id' => '' }, { 'id' => 12 }, { 'id' => 'bad/path' },
     { 'id' => 'build', 'type' => 'apps' }, { 'id' => 'build', 'type' => nil }].each do |linkage|
      @client = BuildLinkageClient.new
      @client.linkages = [linkage]
      assert_raises(M::Error) { runner(apply: true).run }
      assert_empty @client.hydrated_ids
      assert_empty @client.writes
    end
  end
  def test_malformed_or_mismatched_hydrated_identity_fails_before_write
    valid = FakeClient.new.get('/v1/builds/build').fetch('data')
    [nil, [], 'build', {}, valid.merge('id' => 'different'), valid.merge('type' => 'apps'),
     valid.merge('type' => nil), valid.merge('attributes' => nil)].each do |record|
      @client = BuildLinkageClient.new
      @client.records['build'] = record
      assert_raises(M::Error) { runner(apply: true).run }
      assert_equal ['build'], @client.hydrated_ids
      assert_empty @client.writes
    end
  end
  def test_hydrated_build_type_may_be_absent_but_identity_must_match
    @client = BuildLinkageClient.new
    record = FakeClient.new.get('/v1/builds/build').fetch('data')
    record.delete('type')
    @client.records['build'] = record
    instance = runner
    instance.run
    assert_equal 'build', instance.build_id
    assert_equal ['build'], @client.hydrated_ids
    assert_empty @client.writes
  end
  def test_bare_linkage_does_not_bypass_existing_build_eligibility_guards
    [{ processing: 'PROCESSING' }, { audience: 'INTERNAL_ONLY' }, { expired: true }, { binary_version: '2.0.0' }].each do |invalid|
      @client = BuildLinkageClient.new
      invalid.each { |key, value| @client.public_send("#{key}=", value) }
      assert_raises(M::Error) { runner(apply: true).run }
      assert_equal ['build'], @client.hydrated_ids
      assert_empty @client.writes
    end
  end
  def test_wrong_source_commit_fails_before_any_write
    @client.commit = 'b' * 40
    assert_raises(M::Error) { runner(apply: true).run }
    assert_empty @client.writes
  end
  def test_failed_archive_and_wrong_signing_team_fail_before_any_write
    @client.archive = 'FAILED'
    assert_raises(M::Error) { runner(apply: true).run }
    assert_empty @client.writes
    @client.archive = 'SUCCEEDED'
    @client.team = 'WRONGTEAM'
    assert_raises(M::Error) { runner(apply: true).run }
    assert_empty @client.writes
  end
  def test_invalid_internal_expired_or_wrong_version_build_never_writes
    [{ processing: 'PROCESSING' }, { audience: 'INTERNAL_ONLY' }, { expired: true }, { binary_version: '2.0.0' }].each do |invalid|
      @client = FakeClient.new
      invalid.each { |key, value| @client.public_send("#{key}=", value) }
      assert_raises(M::Error) { runner(apply: true).run }
      assert_empty @client.writes
    end
  end
  def test_submission_requires_apply_and_explicit_published_privacy
    assert_raises(M::Error) { runner(submit: true) }
    assert_raises(M::Error) { runner(apply: true, submit: true) }
    assert_empty @client.writes
  end
  def test_keyword_limit_uses_utf8_bytes_before_any_write
    File.write(File.join(@tmp, 'metadata', 'ja', 'keywords.txt'), '語' * 34)
    assert_raises(M::Error) { runner(apply: true).run }
    assert_empty @client.writes
  end
  def test_review_contact_reuse_only_fills_missing_fields
    @client.contacts = { 'contactFirstName' => 'preserved-person', 'contactLastName' => '',
                         'contactPhone' => 'preserved-phone', 'contactEmail' => 'preserved-address' }
    instance = runner(apply: true)
    instance.instance_variable_set(:@version_id, 'version')
    instance.instance_variable_set(:@notes, 'Uniboard review instructions')
    instance.send(:sync_review_detail!)
    attrs = @client.writes.last[2].dig('data', 'attributes')
    assert_equal 'approved-contactLastName', attrs['contactLastName']
    refute attrs.key?('contactFirstName')
    refute attrs.key?('contactPhone')
    refute attrs.key?('contactEmail')
    refute_includes @out.string, 'preserved-address'
    refute_includes @out.string, 'approved-contactLastName'
  end
  def test_initial_release_skips_whats_new_and_keeps_existing_other_fields
    instance = runner(apply: true)
    instance.instance_variable_set(:@version_id, 'version')
    instance.instance_variable_set(:@app_info, { 'id' => 'info' })
    instance.instance_variable_set(:@initial_release, true)
    instance.instance_variable_set(:@metadata, instance.send(:read_metadata))
    instance.send(:sync_metadata!)
    mutations = @client.writes.select { |_, path, _| path.include?('appStoreVersionLocalizations') }
    assert_equal 2, mutations.length
    mutations.each { |_, _, body| refute body['data']['attributes'].key?('whatsNew') }
  end
  def test_api_errors_redact_server_details_and_associated_private_values
    error = M::ApiError.new(409, 'PATCH', '/v1/appStoreReviewDetails/id',
                           'errors' => [{ 'code' => 'INVALID', 'detail' => 'private@example.com' }])
    assert_includes error.message, 'INVALID'
    refute_includes error.message, 'private@example.com'
  end
  def test_signed_upload_refuses_untrusted_host_before_network
    error = assert_raises(M::Error) do
      runner.send(:upload_part!, { 'url' => 'https://attacker.example/signed?token=private', 'method' => 'PUT', 'offset' => 0, 'length' => 1 }, 'a')
    end
    refute_includes error.message, 'token='
  end
  def test_png_transparency_chunk_is_rejected_even_without_alpha_color_type
    chunk = ->(kind) { [0].pack('N') + kind + [0].pack('N') }
    transparent = "\x89PNG\r\n\x1a\n".b + chunk.call('tRNS') + chunk.call('IEND')
    assert_raises(M::Error) { runner.send(:check_png_chunks!, transparent) }
    truncated = "\x89PNG\r\n\x1a\n".b + [100].pack('N') + 'IDAT'
    assert_raises(M::Error) { runner.send(:check_png_chunks!, truncated) }
  end
  def test_submission_readiness_requires_free_current_price_and_enabled_territory
    instance = runner
    instance.instance_variable_set(:@app_info, { 'id' => 'info' })
    instance.instance_variable_set(:@metadata, instance.send(:read_metadata))
    instance.instance_variable_set(:@screenshots, %w[en-US ja].flat_map { |locale| %w[APP_IPHONE_67 APP_IPAD_PRO_3GEN_129].map { |type| { locale: locale, displayType: type } } })
    instance.send(:verify_readiness!)
    @client.price = '0.99'
    assert_raises(M::Error) { instance.send(:verify_readiness!) }
    @client.price = '0.00'
    @client.territory = false
    assert_raises(M::Error) { instance.send(:verify_readiness!) }
    assert_empty @client.writes
  end
  def test_readiness_default_is_get_only_without_any_build_or_contact_access
    client = ReadinessClient.new
    M::ReadinessRunner.new(client: client, out: @out).run
    assert_empty client.writes
    assert_includes @out.string, '2 territories'
    refute_includes @out.string, 'contact'
  end
  def test_readiness_apply_uses_scoped_official_payloads_and_verifies_readback
    client = ReadinessClient.new
    M::ReadinessRunner.new(client: client, apply: true, out: @out).run
    assert_equal 5, client.writes.length
    M::ReadinessRunner::AGE_MILD_FIELDS.each { |key| assert_equal 'INFREQUENT_OR_MILD', client.age_answers[key] }
    assert_equal false, client.age_answers['messagingAndChat']
    assert_equal 'NONE', client.age_answers['violenceRealistic']
    price = client.writes.find { |_, path, _| path == '/v1/appPriceSchedules' }.last
    assert_equal 'usa-free', price.dig('included', 0, 'relationships', 'appPricePoint', 'data', 'id')
    availability = client.writes.find { |_, path, _| path == '/v2/appAvailabilities' }.last
    assert_equal 2, availability['included'].length
    assert availability['included'].all? { |t| t.dig('attributes', 'available') == true && t.dig('attributes', 'preOrderEnabled') == false }
    assert_equal true, availability.dig('data', 'attributes', 'availableInNewTerritories')
    assert_includes @out.string, 'Readiness settings verified'
  end
  def test_readiness_refuses_existing_paid_price_or_availability_restriction_before_writes
    client = ReadinessClient.new
    client.paid_price!
    assert_raises(M::Error) { M::ReadinessRunner.new(client: client, apply: true, out: @out).run }
    assert_empty client.writes
    client = ReadinessClient.new
    client.restricted_availability!
    assert_raises(M::Error) { M::ReadinessRunner.new(client: client, apply: true, out: @out).run }
    assert_empty client.writes
  end
  def review_runner
    @client = ReviewClient.new
    instance = runner
    instance.instance_variable_set(:@version_id, 'version')
    instance.instance_variable_set(:@build_id, 'build')
    instance.instance_variable_set(:@version, @client.get('/v1/appStoreVersions/version')['data'])
    instance
  end
  def test_submission_verification_accepts_official_positive_item_states
    instance = review_runner
    %w[READY_FOR_REVIEW ACCEPTED APPROVED].each do |state|
      @client.item_state = state
      instance.send(:verify_submission!, 'active')
    end
    assert_includes @out.string, 'WAITING_FOR_REVIEW'
    assert_empty @client.writes
  end
  def test_submission_verification_rejects_removed_rejected_missing_and_unknown_item_state
    instance = review_runner
    ['REMOVED', 'REJECTED', nil, 'UNKNOWN'].each do |state|
      @client.item_state = state
      assert_raises(M::Error) { instance.send(:verify_submission!, 'active') }
    end
    assert_empty @out.string
    assert_empty @client.writes
  end
  def test_submission_verification_rejects_unsubmitted_version_even_if_review_resource_is_waiting
    instance = review_runner
    @client.version_state = 'PREPARE_FOR_SUBMISSION'
    assert_raises(M::Error) { instance.send(:verify_submission!, 'active') }
    assert_empty @out.string
    assert_empty @client.writes
  end
  def test_existing_submission_prefers_active_exact_version_over_older_complete_history
    instance = review_runner
    @client.submissions << { 'id' => 'old', 'attributes' => { 'state' => 'COMPLETE', 'submittedDate' => '2026-10-01T10:00:00Z' },
                             'relationships' => { 'appStoreVersionForReview' => { 'data' => { 'id' => 'version' } } } }
    instance.send(:verify_already_submitted!)
    assert_equal ['active'], @client.read_submission_ids
    assert_empty @client.writes
  end
  def test_existing_submission_refuses_ambiguous_active_exact_version
    instance = review_runner
    other = Marshal.load(Marshal.dump(@client.submissions.first))
    other['id'] = 'second-active'
    @client.submissions << other
    assert_raises(M::Error) { instance.send(:verify_already_submitted!) }
    assert_empty @client.read_submission_ids
    assert_empty @client.writes
  end
  def test_review_note_limit_counts_utf8_bytes_before_any_write
    File.write(@notes, '語' * 1334)
    error = assert_raises(M::Error) { runner(apply: true).run }
    assert_includes error.message, '4,000 UTF-8 bytes'
    assert_empty @client.writes
  end
  def metadata_runner
    instance = runner(apply: true)
    instance.instance_variable_set(:@version_id, 'version')
    instance.instance_variable_set(:@app_info, { 'id' => 'info' })
    instance.instance_variable_set(:@initial_release, true)
    instance.instance_variable_set(:@metadata, instance.send(:read_metadata))
    instance
  end
  def test_new_app_info_locale_refreshes_auto_created_version_locale_and_patches_it
    @client = AutomaticLocaleClient.new
    instance = metadata_runner
    instance.send(:sync_metadata!)
    assert @client.writes.any? { |method, path, body| method == 'POST' && path == '/v1/appInfoLocalizations' && body.dig('data', 'attributes', 'locale') == 'ja' }
    patch = @client.writes.find { |method, path, _| method == 'PATCH' && path == '/v1/appStoreVersionLocalizations/version-ja' }
    refute_nil patch
    assert_equal 'Valid listing copy', patch.last.dig('data', 'attributes', 'description')
    refute @client.writes.any? { |method, path, _| method == 'POST' && path == '/v1/appStoreVersionLocalizations' }
    assert_equal 'version-ja', instance.instance_variable_get(:@version_localizations).dig('ja', 'id')
    # A repeated preparation now uses the same resources instead of creating more.
    @client.writes.clear
    instance.send(:sync_metadata!)
    assert @client.writes.all? { |method, _, _| method == 'PATCH' }
  end
  def test_ambiguous_app_info_or_version_locales_fail_before_metadata_writes
    [:duplicate_infos, :duplicate_versions].each do |flag|
      @client = AutomaticLocaleClient.new
      @client.public_send("#{flag}=", true)
      error = assert_raises(M::Error) { metadata_runner.send(:sync_metadata!) }
      assert_includes error.message, 'ambiguous duplicate locale'
      assert_empty @client.writes
    end
  end
end
