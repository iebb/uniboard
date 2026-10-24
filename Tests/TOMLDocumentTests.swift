import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class TOMLDocumentTests: XCTestCase {
    private func parse(_ text: String, limits: TOMLLimits = .standard, file: StaticString = #filePath, line: UInt = #line) -> TOMLTable {
        do { return try TOMLDocument.parse(text, limits: limits) } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
            return TOMLTable()
        }
    }

    private func assertFails(_ text: String, _ reason: TOMLError.Reason, _ errorLine: Int, _ errorColumn: Int,
                             limits: TOMLLimits = .standard, file: StaticString = #filePath, line: UInt = #line) {
        assertFails(Data(text.utf8), reason, errorLine, errorColumn, limits: limits, file: file, line: line)
    }

    private func assertFails(_ data: Data, _ reason: TOMLError.Reason, _ errorLine: Int, _ errorColumn: Int,
                             limits: TOMLLimits = .standard, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try TOMLDocument.parse(data, limits: limits), file: file, line: line) { error in
            XCTAssertEqual(error as? TOMLError, TOMLError(reason: reason, position: TOMLPosition(line: errorLine, column: errorColumn)), file: file, line: line)
        }
    }

    // MARK: toml.io v1.0.0 examples

    func testSpecIntroductionExample() {
        let table = parse(#"""
        # This is a TOML document

        title = "TOML Example"

        [owner]
        name = "Tom Preston-Werner"

        [database]
        enabled = true
        ports = [ 8000, 8001, 8002 ]
        data = [ ["delta", "phi"], [3.14] ]
        temp_targets = { cpu = 79.5, case = 72.0 }

        [servers]

        [servers.alpha]
        ip = "10.0.0.1"
        role = "frontend"

        [servers.beta]
        ip = "10.0.0.2"
        role = "backend"
        """#)
        XCTAssertEqual(table["title"], .string("TOML Example"))
        XCTAssertEqual(table["owner"]?.tableValue?["name"], .string("Tom Preston-Werner"))
        let database = table["database"]?.tableValue
        XCTAssertEqual(database?["enabled"], .boolean(true))
        XCTAssertEqual(database?["ports"], .array([.integer(8000), .integer(8001), .integer(8002)]))
        XCTAssertEqual(database?["data"], .array([.array([.string("delta"), .string("phi")]), .array([.float(3.14)])]))
        XCTAssertEqual(database?["temp_targets"], .table(TOMLTable(["cpu": .float(79.5), "case": .float(72.0)])))
        XCTAssertEqual(table["servers"]?.tableValue?["beta"]?.tableValue?["role"], .string("backend"))
        XCTAssertEqual(table["servers"]?.tableValue?.keys, ["alpha", "beta"])
        XCTAssertEqual(table.keys, ["title", "owner", "database", "servers"])
    }

    func testSpecKeys() {
        let table = parse(#"""
        key = "value"
        bare_key = "value"
        bare-key = "value"
        1234 = "value"
        "127.0.0.1" = "value"
        "character encoding" = "value"
        "ʎǝʞ" = "value"
        'key2' = "value"
        'quoted "value"' = "value"
        "" = "blank"
        physical.color = "orange"
        physical.shape = "round"
        site."google.com" = true
        fruit.name = "banana"     # this is best practice
        fruit. color = "yellow"    # same as fruit.color
        fruit . flavor = "banana"   # same as fruit.flavor
        3.14159 = "pi"
        """#)
        for key in ["key", "bare_key", "bare-key", "1234", "127.0.0.1", "character encoding", "ʎǝʞ", "key2", #"quoted "value""#] {
            XCTAssertEqual(table[key], .string("value"), key)
        }
        XCTAssertEqual(table[""], .string("blank"))
        XCTAssertEqual(table["physical"], .table(TOMLTable(["color": .string("orange"), "shape": .string("round")])))
        XCTAssertEqual(table["site"]?.tableValue?["google.com"], .boolean(true))
        XCTAssertEqual(table["fruit"]?.tableValue?.keys, ["name", "color", "flavor"])
        XCTAssertEqual(table["3"]?.tableValue?["14159"], .string("pi"))

        // Out-of-order dotted keys are valid, if discouraged.
        let fruits = parse("apple.type = \"fruit\"\norange.type = \"fruit\"\napple.skin = \"thin\"\norange.skin = \"thick\"\n")
        XCTAssertEqual(fruits["apple"]?.tableValue?.keys, ["type", "skin"])
        XCTAssertEqual(fruits["orange"]?.tableValue?["skin"], .string("thick"))
    }

    func testSpecKeyErrors() {
        assertFails("key = # INVALID", .expected("a value"), 1, 7)
        assertFails("first = \"Tom\" last = \"Preston-Werner\" # INVALID", .expected("a new line"), 1, 15)
        assertFails("= \"no key name\"", .expected("a key"), 1, 1)
        assertFails("name = \"Tom\"\nname = \"Pradyun\"", .duplicateKey("name"), 2, 1)
        assertFails("spelling = \"favorite\"\n\"spelling\" = \"favourite\"", .duplicateKey("spelling"), 2, 1)
        assertFails("fruit.apple = 1\nfruit.apple.smooth = true", .notATable("fruit.apple"), 2, 7)
        assertFails("a 1", .expected("="), 1, 3)
        assertFails(". = 1", .expected("a key"), 1, 1)
        assertFails("a. = 1", .expected("a key"), 1, 4)
        assertFails("\"\"\"a\"\"\" = 1", .expected("="), 1, 3)
    }

    func testKeysCompareByExactScalars() {
        let table = parse("\"\u{E9}\" = 1\n\"e\\u0301\" = 2\n")
        XCTAssertEqual(table.count, 2)
        XCTAssertEqual(table["\u{E9}"], .integer(1))
        XCTAssertEqual(table["e\u{301}"], .integer(2))
        assertFails("\"\u{E9}\" = 1\n\"\\u00E9\" = 2", .duplicateKey("\"\u{E9}\""), 2, 1)
    }

    func testSpecBasicAndMultilineStrings() {
        let table = parse(#"""
        str = "I'm a string. \"You can quote me\". Name\tJos\u00E9\nLocation\tSF."
        str1 = """
        Roses are red
        Violets are blue"""
        str4 = """Here are two quotation marks: "". Simple enough."""
        str5 = """Here are three quotation marks: ""\"."""
        str6 = """Here are fifteen quotation marks: ""\"""\"""\"""\"""\"."""
        str7 = """"This," she said, "is just a pointless statement.""""
        all = "\b\t\n\f\r\"\\\u00e9\U0001F600"
        """#)
        XCTAssertEqual(table["str"], .string("I'm a string. \"You can quote me\". Name\tJos\u{E9}\nLocation\tSF."))
        XCTAssertEqual(table["str1"], .string("Roses are red\nViolets are blue"))
        XCTAssertEqual(table["str4"], .string("Here are two quotation marks: \"\". Simple enough."))
        XCTAssertEqual(table["str5"], .string("Here are three quotation marks: \"\"\"."))
        XCTAssertEqual(table["str6"], .string("Here are fifteen quotation marks: " + String(repeating: "\"", count: 15) + "."))
        XCTAssertEqual(table["str7"], .string("\"This,\" she said, \"is just a pointless statement.\""))
        XCTAssertEqual(table["all"], .string("\u{08}\t\n\u{0C}\r\"\\\u{E9}\u{1F600}"))
    }

    func testSpecLineEndingBackslash() {
        let table = parse("str1 = \"The quick brown fox jumps over the lazy dog.\"\n"
            + "str2 = \"\"\"\nThe quick brown \\\n\n\n  fox jumps over \\\n    the lazy dog.\"\"\"\n"
            + "str3 = \"\"\"\\\n       The quick brown \\\n       fox jumps over \\\n       the lazy dog.\\\n       \"\"\"\n"
            + "crlf = \"\"\"\r\nThe quick brown \\  \t\r\n  \r\n  fox jumps over the lazy dog.\"\"\"\r\n")
        for key in ["str1", "str2", "str3", "crlf"] {
            XCTAssertEqual(table[key], .string("The quick brown fox jumps over the lazy dog."), key)
        }
    }

    func testMultilineNewlinesAndQuotes() {
        let table = parse("a = \"\"\"\r\nx\r\ny\"\"\"\nb = '''\r\n1\r\n2'''\nc = \"\"\"\"\"\"\nd = \"\"\"\"\"\"\"\ne = '''''''\n")
        XCTAssertEqual(table["a"], .string("x\ny"))
        XCTAssertEqual(table["b"], .string("1\n2"))
        XCTAssertEqual(table["c"], .string(""))
        XCTAssertEqual(table["d"], .string("\""))
        XCTAssertEqual(table["e"], .string("'"))
        // Six quotes at the end: the string closes after five; the sixth is stray.
        assertFails("a = \"\"\"x\"\"\"\"\"\"", .expected("a new line"), 1, 14)
    }

    func testSpecLiteralStrings() {
        let table = parse(#"""
        winpath  = 'C:\Users\nodejs\templates'
        winpath2 = '\\ServerX\admin$\system32\'
        quoted   = 'Tom "Dubs" Preston-Werner'
        regex    = '<\i\c*\s*>'
        regex2 = '''I [dw]on't need \d{2} apples'''
        lines  = '''
        The first newline is
        trimmed in raw strings.
           All other whitespace
           is preserved.
        '''
        quot15 = '''Here are fifteen quotation marks: """""""""""""""'''
        apos15 = "Here are fifteen apostrophes: '''''''''''''''"
        str = ''''That,' she said, 'is still pointless.''''
        """#)
        XCTAssertEqual(table["winpath"], .string(#"C:\Users\nodejs\templates"#))
        XCTAssertEqual(table["winpath2"], .string(#"\\ServerX\admin$\system32\"#))
        XCTAssertEqual(table["quoted"], .string(#"Tom "Dubs" Preston-Werner"#))
        XCTAssertEqual(table["regex"], .string(#"<\i\c*\s*>"#))
        XCTAssertEqual(table["regex2"], .string(#"I [dw]on't need \d{2} apples"#))
        XCTAssertEqual(table["lines"], .string("The first newline is\ntrimmed in raw strings.\n   All other whitespace\n   is preserved.\n"))
        XCTAssertEqual(table["quot15"], .string("Here are fifteen quotation marks: " + String(repeating: "\"", count: 15)))
        XCTAssertEqual(table["apos15"], .string("Here are fifteen apostrophes: " + String(repeating: "'", count: 15)))
        XCTAssertEqual(table["str"], .string("'That,' she said, 'is still pointless.'"))
        assertFails("apos15 = '''Here are fifteen apostrophes: ''''''''''''''''''", .expected("a new line"), 1, 48)
    }

    func testStringErrors() {
        assertFails("a = \"abc", .unterminatedString, 1, 5)
        assertFails("a = '''abc", .unterminatedString, 1, 5)
        assertFails("a = \"x\ny\"", .controlCharacter(0x0A), 1, 7)
        assertFails("a = 'x\ny'", .controlCharacter(0x0A), 1, 7)
        assertFails("a = \"x\u{01}\"", .controlCharacter(0x01), 1, 7)
        assertFails("a = 'x\u{7F}'", .controlCharacter(0x7F), 1, 7)
        assertFails("a = \"\"\"a\rb\"\"\"", .controlCharacter(0x0D), 1, 9)
        assertFails("a = \"\\x41\"", .invalidEscape, 1, 6)
        assertFails("a = \"\\u12\"", .invalidEscape, 1, 6)
        assertFails("a = \"\\u12G4\"", .invalidEscape, 1, 6)
        assertFails("a = \"\\uD800\"", .invalidEscapedScalar, 1, 6)
        assertFails("a = \"\\U00110000\"", .invalidEscapedScalar, 1, 6)
        assertFails("a = \"\\", .invalidEscape, 1, 6)
        assertFails("a = \"\"\"x\\ y\"\"\"", .invalidEscape, 1, 9)
        assertFails("a = \"\"\"x\\\n", .unterminatedString, 1, 5)
        assertFails("a = \"\"\"x\\", .invalidEscape, 1, 9)
        assertFails("a = \"\"\"x\\  ", .invalidEscape, 1, 9)
        // Tabs are allowed raw; escapes stay literal in literal strings.
        let table = parse("a = \"x\ty\"\nb = 'C:\\n'\n")
        XCTAssertEqual(table["a"], .string("x\ty"))
        XCTAssertEqual(table["b"], .string("C:\\n"))
    }

    func testSpecIntegers() {
        let table = parse("""
        int1 = +99
        int2 = 42
        int3 = 0
        int4 = -17
        int5 = 1_000
        int6 = 5_349_221
        int7 = 53_49_221
        int8 = 1_2_3_4_5
        hex1 = 0xDEADBEEF
        hex2 = 0xdeadbeef
        hex3 = 0xdead_beef
        oct1 = 0o01234567
        oct2 = 0o755
        bin1 = 0b11010110
        max = 9_223_372_036_854_775_807
        min = -9_223_372_036_854_775_808
        plus0 = +0
        minus0 = -0
        hexmax = 0x7FFFFFFFFFFFFFFF
        """)
        let expected: [String: Int64] = ["int1": 99, "int2": 42, "int3": 0, "int4": -17, "int5": 1000, "int6": 5_349_221,
                                         "int7": 5_349_221, "int8": 12345, "hex1": 0xDEADBEEF, "hex2": 0xDEADBEEF, "hex3": 0xDEADBEEF,
                                         "oct1": 0o01234567, "oct2": 0o755, "bin1": 0b11010110, "max": .max, "min": .min,
                                         "plus0": 0, "minus0": 0, "hexmax": .max]
        for (key, value) in expected { XCTAssertEqual(table[key], .integer(value), key) }
    }

    func testIntegerErrors() {
        assertFails("a = 9223372036854775808", .numberOutOfRange, 1, 5)
        assertFails("a = -9223372036854775809", .numberOutOfRange, 1, 5)
        assertFails("a = 0x8000000000000000", .numberOutOfRange, 1, 5)
        for bad in ["012", "1__2", "_1", "1_", "+0x1", "0o8", "0b2", "0X1", "+", "0x", "True", "infinity", "1+2"] {
            assertFails("a = " + bad, .invalidNumber, 1, 5)
        }
        assertFails("a = 1 2", .expected("a new line"), 1, 7)
    }

    func testSpecFloats() {
        let table = parse("""
        flt1 = +1.0
        flt2 = 3.1415
        flt3 = -0.01
        flt4 = 5e+22
        flt5 = 1e06
        flt6 = -2E-2
        flt7 = 6.626e-34
        flt8 = 224_617.445_991_228
        flt9 = 1e1_0
        sf1 = inf
        sf2 = +inf
        sf3 = -inf
        sf4 = nan
        sf5 = +nan
        sf6 = -nan
        zero = -0.0
        """)
        let expected: [String: Double] = ["flt1": 1, "flt2": 3.1415, "flt3": -0.01, "flt4": 5e22, "flt5": 1e6, "flt6": -0.02,
                                          "flt7": 6.626e-34, "flt8": 224_617.445_991_228, "flt9": 1e10,
                                          "sf1": .infinity, "sf2": .infinity, "sf3": -.infinity]
        for (key, value) in expected { XCTAssertEqual(table[key], .float(value), key) }
        for key in ["sf4", "sf5", "sf6"] { XCTAssertEqual(table[key]?.floatValue?.isNaN, true, key) }
        XCTAssertEqual(table["zero"]?.floatValue?.sign, .minus)
        XCTAssertNotEqual(table["zero"], .float(0))
    }

    func testFloatErrors() {
        for bad in [".7", "7.", "3.e+20", "1e", "1e+", "01.5", "1.2.3", "1e_5", "1e5.0", "1._5", "-.5"] {
            assertFails("a = " + bad, .invalidNumber, 1, 5)
        }
        assertFails("a = 1e400", .numberOutOfRange, 1, 5)
    }

    func testDatesAndTimesAreRejected() {
        assertFails("odt1 = 1979-05-27T07:32:00Z", .dateTimeUnsupported, 1, 8)
        assertFails("ldt1 = 1979-05-27 07:32:00", .dateTimeUnsupported, 1, 8)
        assertFails("ld1 = 1979-05-27", .dateTimeUnsupported, 1, 7)
        assertFails("lt1 = 07:32:00", .dateTimeUnsupported, 1, 7)
        assertFails("""
        # Top-level table begins.
        name = "Fido"
        breed = "pug"

        # Top-level table ends.
        [owner]
        name = "Regina Dogman"
        member_since = 1999-08-04
        """, .dateTimeUnsupported, 8, 16)
        // Four digits are an ordinary integer.
        XCTAssertEqual(parse("year = 1979")["year"], .integer(1979))
    }

    func testSpecBooleansAndArrays() {
        let table = parse(#"""
        bool1 = true
        bool2 = false
        integers = [ 1, 2, 3 ]
        colors = [ "red", "yellow", "green" ]
        nested_arrays_of_ints = [ [ 1, 2 ], [3, 4, 5] ]
        nested_mixed_array = [ [ 1, 2 ], ["a", "b", "c"] ]
        string_array = [ "all", 'strings', """are the same""", '''type''' ]
        numbers = [ 0.1, 0.2, 0.5, 1, 2, 5 ]
        contributors = [
          "Foo Bar <foo@example.com>",
          { name = "Baz Qux", email = "bazqux@example.com", url = "https://example.com/bazqux" }
        ]
        integers2 = [
          1, 2, 3
        ]
        integers3 = [
          1,
          2, # this is ok
        ]
        empty = [ ]
        """#)
        XCTAssertEqual(table["bool1"], .boolean(true))
        XCTAssertEqual(table["bool2"], .boolean(false))
        XCTAssertEqual(table["string_array"], .array(["all", "strings", "are the same", "type"].map { .string($0) }))
        XCTAssertEqual(table["numbers"], .array([.float(0.1), .float(0.2), .float(0.5), .integer(1), .integer(2), .integer(5)]))
        XCTAssertEqual(table["contributors"]?.arrayValue?.count, 2)
        XCTAssertEqual(table["contributors"]?.arrayValue?[1].tableValue?["name"], .string("Baz Qux"))
        XCTAssertEqual(table["integers2"], table["integers"])
        XCTAssertEqual(table["integers3"], .array([.integer(1), .integer(2)]))
        XCTAssertEqual(table["empty"], .array([]))
        XCTAssertEqual(table["nested_mixed_array"]?.arrayValue?[1], .array([.string("a"), .string("b"), .string("c")]))
        let crlf = parse("a = [\r\n  1, # one\r\n  2\r\n]\r\n")
        XCTAssertEqual(crlf["a"], .array([.integer(1), .integer(2)]))
    }

    func testArrayErrors() {
        assertFails("a = [1 2]", .expected("a comma or ]"), 1, 8)
        assertFails("a = [1,,2]", .expected("a value"), 1, 8)
        assertFails("a = [", .expected("a value"), 1, 6)
        assertFails("a = [1, # \u{01}\n]", .controlCharacter(0x01), 1, 11)
    }

    func testSpecTables() {
        let table = parse(#"""
        [table-1]
        key1 = "some string"
        key2 = 123

        [table-2]
        key1 = "another string"
        key2 = 456

        [dog."tater.man"]
        type.name = "pug"

        [a.b.c]            # this is best practice
        [ d.e.f ]          # same as [d.e.f]
        [ g .  h  . i ]    # same as [g.h.i]
        [ j . "ʞ" . 'l' ]  # same as [j."ʞ".l]

        # [x] you
        # [x.y] don't
        # [x.y.z] need these
        [x.y.z.w] # for this to work

        [x] # defining a super-table afterward is ok
        """#)
        XCTAssertEqual(table["table-2"]?.tableValue?["key2"], .integer(456))
        XCTAssertEqual(table["dog"]?.tableValue?["tater.man"]?.tableValue?["type"]?.tableValue?["name"], .string("pug"))
        XCTAssertEqual(table["a"]?.tableValue?["b"]?.tableValue?["c"], .table(TOMLTable()))
        XCTAssertEqual(table["g"]?.tableValue?["h"]?.tableValue?["i"], .table(TOMLTable()))
        XCTAssertEqual(table["j"]?.tableValue?["ʞ"]?.tableValue?["l"], .table(TOMLTable()))
        XCTAssertNotNil(table["x"]?.tableValue?["y"]?.tableValue?["z"]?.tableValue?["w"])

        let fruit = parse("""
        [fruit]
        apple.color = "red"
        apple.taste.sweet = true

        [fruit.apple.texture]  # you can add sub-tables
        smooth = true
        """)
        XCTAssertEqual(fruit["fruit"]?.tableValue?["apple"]?.tableValue?["texture"]?.tableValue?["smooth"], .boolean(true))
        XCTAssertEqual(fruit["fruit"]?.tableValue?["apple"]?.tableValue?["taste"]?.tableValue?["sweet"], .boolean(true))
    }

    func testTableErrors() {
        assertFails("[fruit]\napple = \"red\"\n\n[fruit]\norange = \"orange\"", .tableRedefined("fruit"), 4, 2)
        assertFails("[fruit]\napple = \"red\"\n\n[fruit.apple]\ntexture = \"smooth\"", .tableRedefined("fruit.apple"), 4, 8)
        assertFails("[fruit]\napple.color = \"red\"\n[fruit.apple]", .tableRedefined("fruit.apple"), 3, 8)
        assertFails("[fruit]\napple.color = \"red\"\n[fruit.apple.color]", .tableRedefined("fruit.apple.color"), 3, 14)
        assertFails("a.b = 1\n[a]", .tableRedefined("a"), 2, 2)
        assertFails("a = 1\n[a.b]", .notATable("a"), 2, 2)
        assertFails("a = {}\n[a.b]", .notATable("a"), 2, 2)
        assertFails("[a.b]\n[a]\n[a]", .tableRedefined("a"), 3, 2)
        assertFails("[a.b.c]\nz = 9\n[a]\nb.c.t = 1", .notATable("a.b"), 4, 1)
        assertFails("[a.b.c]\n[a]\nb.d = 1", .notATable("a.b"), 3, 1)
        assertFails("[a]]", .expected("a new line"), 1, 4)
        assertFails("[a", .expected("]"), 1, 3)
        assertFails("[[a]", .expected("]]"), 1, 5)
        assertFails("[[a] ]", .expected("]]"), 1, 5)
        assertFails("[]", .expected("a key"), 1, 2)
        // A header defined implicitly may be defined once, later.
        let table = parse("[a.b]\nc = 1\n[a]\nd = 2\n")
        XCTAssertEqual(table["a"]?.tableValue?.keys, ["b", "d"])
    }

    func testSpecInlineTables() {
        let table = parse("""
        name = { first = "Tom", last = "Preston-Werner" }
        point = { x = 1, y = 2 }
        animal = { type.name = "pug" }
        empty = {}
        spaced = { }
        dotted = { a.b = 1, a.c = 2 }
        nested = { a = { b = [ { c = 1 } ] } }
        """)
        XCTAssertEqual(table["name"]?.tableValue?["last"], .string("Preston-Werner"))
        XCTAssertEqual(table["animal"]?.tableValue?["type"]?.tableValue?["name"], .string("pug"))
        XCTAssertEqual(table["empty"], .table(TOMLTable()))
        XCTAssertEqual(table["spaced"], .table(TOMLTable()))
        XCTAssertEqual(table["dotted"]?.tableValue?["a"], .table(TOMLTable(["b": .integer(1), "c": .integer(2)])))
        XCTAssertEqual(table["nested"]?.tableValue?["a"]?.tableValue?["b"], .array([.table(TOMLTable(["c": .integer(1)]))]))
    }

    func testInlineTableErrors() {
        assertFails("[product]\ntype = { name = \"Nail\" }\ntype.edible = false", .notATable("product.type"), 3, 1)
        assertFails("[product]\ntype.name = \"Nail\"\ntype = { edible = false }", .duplicateKey("product.type"), 3, 1)
        assertFails("a = {b = 1,}", .expected("a key"), 1, 12)
        assertFails("a = {b = 1\n}", .expected("a comma or }"), 1, 11)
        assertFails("a = {b = 1", .expected("a comma or }"), 1, 11)
        assertFails("a = {b = {}, b.c = 1}", .notATable("b"), 1, 14)
        assertFails("a = {b = 1, b = 2}", .duplicateKey("b"), 1, 13)
    }

    func testSpecArraysOfTables() {
        let products = parse("""
        [[products]]
        name = "Hammer"
        sku = 738594937

        [[products]]  # empty table within the array

        [[products]]
        name = "Nail"
        sku = 284758393

        color = "gray"
        """)
        XCTAssertEqual(products["products"]?.arrayValue?.count, 3)
        XCTAssertEqual(products["products"]?.arrayValue?[1], .table(TOMLTable()))
        XCTAssertEqual(products["products"]?.arrayValue?[2].tableValue?["color"], .string("gray"))

        let fruits = parse("""
        [[fruits]]
        name = "apple"

        [fruits.physical]  # subtable
        color = "red"
        shape = "round"

        [[fruits.varieties]]  # nested array of tables
        name = "red delicious"

        [[fruits.varieties]]
        name = "granny smith"


        [[fruits]]
        name = "banana"

        [[fruits.varieties]]
        name = "plantain"
        """)
        let list = fruits["fruits"]?.arrayValue
        XCTAssertEqual(list?.count, 2)
        XCTAssertEqual(list?[0].tableValue?["physical"]?.tableValue?["shape"], .string("round"))
        XCTAssertEqual(list?[0].tableValue?["varieties"]?.arrayValue?.count, 2)
        XCTAssertEqual(list?[1].tableValue?["varieties"], .array([.table(TOMLTable(["name": .string("plantain")]))]))
    }

    func testArrayOfTablesErrors() {
        assertFails("[fruit.physical]\ncolor = \"red\"\nshape = \"round\"\n\n[[fruit]]\nname = \"apple\"", .tableRedefined("fruit"), 5, 3)
        assertFails("fruits = []\n\n[[fruits]] # Not allowed", .tableRedefined("fruits"), 3, 3)
        assertFails("[[fruits]]\nname = \"apple\"\n\n[[fruits.varieties]]\nname = \"red delicious\"\n\n"
                    + "# INVALID: This table conflicts with the previous array of tables\n[fruits.varieties]\nname = \"granny smith\"",
                    .tableRedefined("fruits.varieties"), 8, 9)
        assertFails("[[fruits]]\n[fruits.physical]\ncolor = \"red\"\n[[fruits.physical]]", .tableRedefined("fruits.physical"), 4, 10)
    }

    // MARK: Layout, encoding and limits

    func testCommentsWhitespaceAndLineEndings() {
        let table = parse("# comment\r\n\t a = 1 # trailing\r\n\r\n[t] # header\r\n b = \"#not a comment\"\n# last")
        XCTAssertEqual(table["a"], .integer(1))
        XCTAssertEqual(table["t"]?.tableValue?["b"], .string("#not a comment"))
        assertFails("# \u{07}", .controlCharacter(0x07), 1, 3)
        assertFails("# a\rb", .controlCharacter(0x0D), 1, 4)
        assertFails("a = 1\r", .expected("a new line"), 1, 6)
        assertFails("\r", .expected("a key"), 1, 1)
        XCTAssertEqual(parse(""), TOMLTable())
        XCTAssertEqual(parse("\n\n# only comments\n"), TOMLTable())
    }

    func testPositionsCountScalarsAndCRLF() {
        let table = parse("a = 1\r\n[t]\r\n  \"ᚠᚢ\" = 2\n")
        XCTAssertEqual(table.position(of: "a"), TOMLPosition(line: 1, column: 1))
        XCTAssertEqual(table.position(of: "t"), TOMLPosition(line: 2, column: 2))
        XCTAssertEqual(table["t"]?.tableValue?.position(of: "ᚠᚢ"), TOMLPosition(line: 3, column: 3))
        XCTAssertNil(table.position(of: "missing"))
        assertFails("a = \"😀😀\" x", .expected("a new line"), 1, 10)
    }

    func testByteOrderMarkAndUTF8() {
        XCTAssertEqual(parse("\u{FEFF}a = 1")["a"], .integer(1))
        assertFails("\u{FEFF}a = ", .expected("a value"), 1, 5)
        XCTAssertEqual(parse("a = \"\u{FEFF}\"")["a"], .string("\u{FEFF}"))
        assertFails("\u{FEFF}\u{FEFF}a = 1", .expected("a key"), 1, 1)
        assertFails(Data([0x61, 0x20, 0x3D, 0x20, 0x22, 0xFF, 0x22]), .invalidUTF8, 1, 6)
        assertFails(Data("a = 1\n".utf8) + Data([0xC0, 0x80]), .invalidUTF8, 2, 1)
        assertFails(Data("a = \"".utf8) + Data([0xED, 0xA0, 0x80, 0x22]), .invalidUTF8, 1, 6)
        assertFails(Data([0xEF, 0xBB, 0xBF, 0xFF]), .invalidUTF8, 1, 1)
    }

    func testLimitsAreErrorsNotTruncation() {
        var limits = TOMLLimits()
        XCTAssertEqual(TOMLLimits.standard.maximumBytes, 4_000_000)
        limits.maximumBytes = 4
        assertFails("a = 1", .tooLarge(limit: 4), 1, 1, limits: limits)
        XCTAssertEqual(parse("a=1", limits: limits)["a"], .integer(1))

        limits = TOMLLimits()
        limits.maximumDepth = 2
        assertFails("[a.b.c]", .tooDeep(limit: 2), 1, 1, limits: limits)
        assertFails("a = [[[1]]]", .tooDeep(limit: 2), 1, 8, limits: limits)
        assertFails("a.b.c.d = 1", .tooDeep(limit: 2), 1, 11, limits: limits)
        assertFails("a = { b = { c = { d = 1 } } }", .tooDeep(limit: 2), 1, 23, limits: limits)
        assertFails("[a]\n[[a.b]]", .tooDeep(limit: 2), 2, 1, limits: limits)
        assertFails("[x.y]\n[x]\n[x.y.z]", .tooDeep(limit: 2), 3, 1, limits: limits)
        XCTAssertNotNil(parse("[a.b]\nc = 1\n[a]\n[[d]]", limits: limits)["d"])

        limits = TOMLLimits()
        limits.maximumKeyBytes = 3
        assertFails("abcd = 1", .keyTooLong(limit: 3), 1, 1, limits: limits)
        assertFails("a.\"ééé\" = 1", .keyTooLong(limit: 3), 1, 3, limits: limits)

        limits = TOMLLimits()
        limits.maximumStringBytes = 3
        assertFails("a = \"abcd\"", .stringTooLong(limit: 3), 1, 5, limits: limits)
        assertFails("a = 'é😀'", .stringTooLong(limit: 3), 1, 5, limits: limits)

        limits = TOMLLimits()
        limits.maximumArrayElements = 2
        assertFails("a = [1, 2, 3]", .arrayTooLong(limit: 2), 1, 12, limits: limits)
        assertFails("[[t]]\n[[t]]\n[[t]]", .arrayTooLong(limit: 2), 3, 1, limits: limits)

        limits = TOMLLimits()
        limits.maximumValues = 2
        assertFails("a = 1\nb = 2\nc = 3", .tooManyValues(limit: 2), 3, 5, limits: limits)
        assertFails("a = [1]\nb = 2", .tooManyValues(limit: 2), 2, 5, limits: limits)
    }

    func testDocumentedImportLimit() throws {
        let maximal = Data("#".utf8) + Data(repeating: 0x78, count: 3_999_999)
        XCTAssertEqual(try TOMLDocument.parse(maximal), TOMLTable())
        assertFails(maximal + Data([0x0A]), .tooLarge(limit: 4_000_000), 1, 1)
    }

    func testErrorMessagesAndDescription() {
        let reasons: [TOMLError.Reason] = [
            .tooLarge(limit: 4_000_000), .invalidUTF8, .controlCharacter(1), .expected("="), .unterminatedString, .invalidEscape,
            .invalidEscapedScalar, .invalidNumber, .numberOutOfRange, .dateTimeUnsupported, .duplicateKey("a"), .tableRedefined("a"),
            .notATable("a"), .tooDeep(limit: 16), .keyTooLong(limit: 256), .stringTooLong(limit: 65_536), .arrayTooLong(limit: 8_192),
            .tooManyValues(limit: 500_000)
        ]
        let messages = reasons.map { TOMLError(reason: $0, position: TOMLPosition(line: 1, column: 1)).message }
        XCTAssertEqual(Set(messages).count, reasons.count)
        XCTAssertTrue(messages.allSatisfy { $0.hasSuffix(".") })
        XCTAssertEqual(messages[2], "The control character U+0001 must be escaped.")
        let error = TOMLError(reason: .expected("="), position: TOMLPosition(line: 3, column: 7))
        XCTAssertEqual(error.description, "Check line 3, column 7: Expected =.")
    }

    // MARK: Values and tables

    func testValueAccessorsAndEquality() {
        let values: [TOMLValue] = [.string("a"), .integer(1), .float(1.5), .boolean(true), .array([.integer(1)]), .table(TOMLTable(["a": .integer(1)]))]
        XCTAssertEqual(values.map(\.stringValue), ["a", nil, nil, nil, nil, nil])
        XCTAssertEqual(values.map(\.integerValue), [nil, 1, nil, nil, nil, nil])
        XCTAssertEqual(values.map(\.floatValue), [nil, nil, 1.5, nil, nil, nil])
        XCTAssertEqual(values.map(\.booleanValue), [nil, nil, nil, true, nil, nil])
        XCTAssertEqual(values.compactMap(\.arrayValue).count, 1)
        XCTAssertEqual(values.compactMap(\.tableValue).count, 1)
        for (offset, value) in values.enumerated() {
            for (other, candidate) in values.enumerated() { XCTAssertEqual(value == candidate, offset == other) }
        }
        XCTAssertNotEqual(TOMLValue.string("\u{E9}"), .string("e\u{301}"))
        XCTAssertEqual(TOMLValue.float(.nan), .float(-.nan))
        XCTAssertNotEqual(TOMLValue.float(0), .float(-0.0))
        XCTAssertNotEqual(TOMLValue.integer(1), .integer(2))
        XCTAssertNotEqual(TOMLValue.boolean(true), .boolean(false))
        XCTAssertNotEqual(TOMLValue.array([.integer(1)]), .array([.integer(1), .integer(2)]))
    }

    func testTableEditingAndEquality() {
        var table = TOMLTable(["a": .integer(1), "b": .integer(2)])
        XCTAssertEqual(table.count, 2)
        XCTAssertFalse(table.isEmpty)
        XCTAssertTrue(TOMLTable().isEmpty)
        table["a"] = .integer(3)
        XCTAssertEqual(table.keys, ["a", "b"])
        XCTAssertEqual(table.entries.map { $0.key }, ["a", "b"])
        XCTAssertEqual(table.entries.map { $0.value }, [.integer(3), .integer(2)])
        table["c"] = .string("x")
        XCTAssertEqual(table.keys, ["a", "b", "c"])
        table["b"] = nil
        table["missing"] = nil
        XCTAssertEqual(table.keys, ["a", "c"])
        XCTAssertNil(table["b"])
        // Order doesn't matter for equality; content does.
        XCTAssertEqual(table, TOMLTable(["c": .string("x"), "a": .integer(3)]))
        XCTAssertNotEqual(table, TOMLTable(["c": .string("x"), "a": .integer(4)]))
        XCTAssertNotEqual(table, TOMLTable(["c": .string("x")]))
        XCTAssertNotEqual(table, TOMLTable(["c": .string("x"), "d": .integer(3)]))
        var positioned = parse("a = 1\nb = 2")
        positioned["a"] = nil
        XCTAssertNil(positioned.position(of: "a"))
        XCTAssertEqual(positioned.position(of: "b"), TOMLPosition(line: 2, column: 1))
    }

    // MARK: Writing

    func testWriterIsDeterministicAndReadable() {
        var root = TOMLTable()
        root["schema_version"] = .integer(1)
        root["settings"] = .table(TOMLTable(["extra_unicode_fonts": .boolean(false), "name": .string("a\"b")]))
        root["favorites"] = .table(TOMLTable(["texts": .array([.string("★"), .string("👩\u{200D}💻"), .string("❤\u{FE0F}")])]))
        root["font_rules"] = .table(TOMLTable(["rule": .array([
            .table(TOMLTable(["code_point": .string("U+16A0"), "font": .string("font-1")])),
            .table(TOMLTable(["range": .array([.string("U+2190"), .string("U+21FF")])]))
        ])]))
        let expected = """
        schema_version = 1

        [settings]
        extra_unicode_fonts = false
        name = "a\\"b"

        [favorites]
        texts = ["★", "👩\\u200D💻", "❤\\uFE0F"]

        [[font_rules.rule]]
        code_point = "U+16A0"
        font = "font-1"

        [[font_rules.rule]]
        range = ["U+2190", "U+21FF"]

        """
        XCTAssertEqual(TOMLDocument.write(root), expected)
        XCTAssertEqual(parse(expected), root)
        XCTAssertEqual(TOMLDocument.write(parse(expected)), expected)
    }

    func testWriterEscapesInvisibleAndControlScalars() {
        XCTAssertEqual(TOMLWriter.quoted("\"\\\u{08}\t\n\u{0C}\r"), #""\"\\\b\t\n\f\r""#)
        XCTAssertEqual(TOMLWriter.quoted("\u{01}\u{1F}\u{7F}\u{85}\u{AD}\u{61C}\u{180E}"), #""\u0001\u001F\u007F\u0085\u00AD\u061C\u180E""#)
        XCTAssertEqual(TOMLWriter.quoted("\u{200B}\u{200C}\u{200D}\u{200E}\u{202E}\u{2028}\u{2060}\u{2066}\u{FEFF}"),
                       #""\u200B\u200C\u200D\u200E\u202E\u2028\u2060\u2066\uFEFF""#)
        XCTAssertEqual(TOMLWriter.quoted("\u{FE0E}\u{FE0F}\u{E0001}\u{E0067}\u{E007F}\u{E0100}\u{E01EF}"),
                       #""\uFE0E\uFE0F\U000E0001\U000E0067\U000E007F\U000E0100\U000E01EF""#)
        XCTAssertEqual(TOMLWriter.quoted("é😀ᚠ中\u{10FFFF}"), "\"é😀ᚠ中\u{10FFFF}\"")
        XCTAssertEqual(TOMLWriter.key("bare-key_1"), "bare-key_1")
        XCTAssertEqual(TOMLWriter.key(""), "\"\"")
        XCTAssertEqual(TOMLWriter.key("a b"), "\"a b\"")
        XCTAssertEqual(TOMLWriter.key("é"), "\"é\"")
        XCTAssertEqual(TOMLWriter.key("a.b"), "\"a.b\"")
    }

    func testWriterNumbersAndInlineValues() {
        XCTAssertEqual(TOMLWriter.float(.nan), "nan")
        XCTAssertEqual(TOMLWriter.float(.infinity), "inf")
        XCTAssertEqual(TOMLWriter.float(-.infinity), "-inf")
        XCTAssertEqual(TOMLWriter.float(700), "700.0")
        XCTAssertEqual(TOMLWriter.float(-0.0), "-0.0")
        for value in [0.1, 1e16, 1e-7, 5e-324, 1.7976931348623157e308, -2.5e-3, 123456.789] {
            XCTAssertEqual(parse("a = " + TOMLWriter.float(value))["a"], .float(value), "\(value)")
        }
        XCTAssertEqual(TOMLWriter.inline(.integer(-5)), "-5")
        XCTAssertEqual(TOMLWriter.inline(.boolean(true)), "true")
        XCTAssertEqual(TOMLWriter.inline(.boolean(false)), "false")
        XCTAssertEqual(TOMLWriter.inline(.table(TOMLTable())), "{}")
        XCTAssertEqual(TOMLWriter.inline(.table(TOMLTable(["a": .integer(1), "b c": .array([])]))), "{ a = 1, \"b c\" = [] }")
        let long = TOMLValue.array((0..<12).map { .string("item-\($0)") })
        XCTAssertTrue(TOMLWriter.inline(long).hasPrefix("[\n  \"item-0\",\n"))
        XCTAssertTrue(TOMLWriter.inline(long).hasSuffix("  \"item-11\",\n]"))
        XCTAssertEqual(parse("a = " + TOMLWriter.inline(long))["a"], long)
    }

    func testWriterRoundTripsEveryShape() {
        var page = TOMLTable()
        page["id"] = .string("stock-symbols")
        page["key"] = .array([.table(TOMLTable(["id": .string("k1"), "text": .string("!"), "up": .array([])])),
                              .table(TOMLTable(["id": .string("k2"), "text": .string("e\u{301}"), "variants": .array([.string("👩\u{200D}👩\u{200D}👧"), .string("\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}")])]))])
        var root = TOMLTable()
        root["mixed"] = .array([.integer(1), .table(TOMLTable(["a": .string("x")])), .array([]), .float(.infinity)])
        root["empty_list"] = .array([])
        root["pages"] = .table(TOMLTable(["page": .array([.table(page), .table(TOMLTable())]), "star_page": .string("x")]))
        root["empty"] = .table(TOMLTable())
        root["deep"] = .table(TOMLTable(["only": .table(TOMLTable(["tables": .table(TOMLTable(["v": .integer(1)]))]))]))
        root["control"] = .string("a\u{0}b\u{1B}c\u{2028}")
        root["quoted key"] = .table(TOMLTable(["é": .boolean(true)]))
        let text = TOMLDocument.write(root)
        let reparsed = parse(text)
        XCTAssertEqual(reparsed, root)
        XCTAssertEqual(TOMLDocument.write(reparsed), text)
        XCTAssertTrue(text.contains("[deep.only.tables]\nv = 1\n"))
        XCTAssertFalse(text.contains("[deep]"))
        XCTAssertTrue(text.contains("\n[empty]\n"))
        XCTAssertTrue(text.contains("[[pages.page.key]]"))
        XCTAssertTrue(text.contains("[\"quoted key\"]\n\"é\" = true"))
        XCTAssertTrue(text.contains(#"control = "a\u0000b\u001Bc\u2028""#))
        // A document that starts with a table has no leading blank line.
        XCTAssertEqual(TOMLDocument.write(TOMLTable(["t": .table(TOMLTable(["a": .integer(1)]))])), "[t]\na = 1\n")
        XCTAssertEqual(TOMLDocument.write(TOMLTable(["t": .array([.table(TOMLTable())])])), "[[t]]\n")
    }

    func testRoundTripPreservesExactUnicodeSequences() {
        let samples = ["e\u{301}", "\u{E9}", "👩\u{200D}💻", "❤\u{FE0E}", "❤\u{FE0F}", "\u{10FFFF}", "\u{1F600}", "\u{0}", "\u{7F}",
                       "a\u{202E}b", "\u{E0100}", "ᚠ\u{200C}ᚢ", "\\\"'", "line\nbreak\r\ttab", "\u{1F1FA}\u{1F1F8}", "中文", "\u{FFFD}"]
        let table = TOMLTable(["texts": .array(samples.map { .string($0) })])
        let reparsed = parse(TOMLDocument.write(table))
        let texts = reparsed["texts"]?.arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertEqual(texts.map { Array($0.unicodeScalars) }, samples.map { Array($0.unicodeScalars) })
    }
}
