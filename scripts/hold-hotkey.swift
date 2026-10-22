// ⌥V を、Kasane より先に「排他で」押さえておく確認用のスクリプト。
// Kasane がほかのアプリとショートカットがぶつかったときに、メニューに「使用中」と出すかを確かめるために使う（manual-test 9 章）。
//
//   swift scripts/hold-hotkey.swift    # Control+C で止めると、⌥V を離す
import Carbon.HIToolbox
import Foundation

var ref: EventHotKeyRef?
let id = EventHotKeyID(signature: OSType(0x4B53_5448), id: 1) // 'KSTH'
let status = RegisterEventHotKey(
    UInt32(kVK_ANSI_V), UInt32(optionKey), id, GetApplicationEventTarget(),
    OptionBits(kEventHotKeyExclusive), &ref
)
guard status == noErr else {
    print("⌥V を押さえられませんでした（\(status)）。Kasane が動いていたら終了してから、もう一度流してください")
    exit(1)
}
print("⌥V を押さえました。このターミナルは開いたままにしてください。Control+C で離します")
RunLoop.main.run()
