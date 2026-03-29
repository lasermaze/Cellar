import Testing
@testable import cellar

@Suite("Dialog Parsing Tests")
struct DialogParsingTests {

    // MARK: - parseMsgboxDialogs tests

    @Test("parses a single msgbox line and extracts message text")
    func parseSingleMsgboxLine() {
        let lines = [
            "0009:trace:msgbox:MSGBOX_OnInit L\"Microsoft Mathematics has encountered a problem.\""
        ]
        let dialogs = AgentTools.parseMsgboxDialogs(from: lines)
        #expect(dialogs.count == 1)
        #expect(dialogs[0]["message"] == "Microsoft Mathematics has encountered a problem.")
        #expect(dialogs[0]["source"] == "trace:msgbox")
    }

    @Test("unescapes Wine escape sequences (newline, tab, backslash)")
    func unescapesWineEscapeSequences() {
        let lines = [
            #"0009:trace:msgbox:MSGBOX_OnInit L"Runtime error!\n\nProgram: C:\\Program Files\\game.exe\nabnormal program termination\n""#
        ]
        let dialogs = AgentTools.parseMsgboxDialogs(from: lines)
        #expect(dialogs.count == 1)
        let msg = dialogs[0]["message"]!
        #expect(msg.contains("\n"))
        #expect(msg.contains("C:\\Program Files\\game.exe"))
        #expect(!msg.contains("\\n"))
        // The leading/trailing escaped newlines should be unescaped
        #expect(msg.contains("abnormal program termination"))
    }

    @Test("parses multiple msgbox lines from stderr")
    func parsesMultipleMsgboxLines() {
        let lines = [
            "0001:trace:loaddll:load_dll Loaded L\"kernel32.dll\"",
            "0009:trace:msgbox:MSGBOX_OnInit L\"First dialog message\"",
            "000a:trace:msgbox:MSGBOX_OnInit L\"Second dialog message\"",
            "0009:err:module:import_dll Loading library msvcr120.dll failed"
        ]
        let dialogs = AgentTools.parseMsgboxDialogs(from: lines)
        #expect(dialogs.count == 2)
        #expect(dialogs[0]["message"] == "First dialog message")
        #expect(dialogs[1]["message"] == "Second dialog message")
    }

    @Test("returns empty array when no msgbox lines present")
    func returnsEmptyForNoMsgboxLines() {
        let lines = [
            "0001:trace:loaddll:load_dll Loaded L\"kernel32.dll\"",
            "0009:err:module:import_dll Loading library msvcr120.dll failed",
            ""
        ]
        let dialogs = AgentTools.parseMsgboxDialogs(from: lines)
        #expect(dialogs.isEmpty)
    }

    @Test("handles both hex TID and decimal dot TID formats")
    func handlesBothTIDFormats() {
        let lines = [
            "0009:trace:msgbox:MSGBOX_OnInit L\"Hex TID format\"",
            "3828042.6030024:trace:msgbox:MSGBOX_OnInit L\"Decimal dot format\""
        ]
        let dialogs = AgentTools.parseMsgboxDialogs(from: lines)
        #expect(dialogs.count == 2)
        #expect(dialogs[0]["message"] == "Hex TID format")
        #expect(dialogs[1]["message"] == "Decimal dot format")
    }

    @Test("handles tab escape sequences")
    func handlesTabEscapes() {
        let lines = [
            #"0009:trace:msgbox:MSGBOX_OnInit L"Column1\tColumn2\tColumn3""#
        ]
        let dialogs = AgentTools.parseMsgboxDialogs(from: lines)
        #expect(dialogs.count == 1)
        #expect(dialogs[0]["message"] == "Column1\tColumn2\tColumn3")
    }
}
