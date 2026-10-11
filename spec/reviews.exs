# Requirements checked by hand, by requirement ID.
#
# Use this for requirements that tests can't fully cover. Say what was
# checked and how. A requirement whose tests pass doesn't need a review,
# but a review can add what the tests miss (e.g. the browser side).
#
# Update or remove a review when its requirement changes.
%{
  "ARCH-6" =>
    "The browser keeps only the open SerialPort, its reader and writer " <>
      "(lib/assets/serial_cell/main.js). Port, subscriber, request queue, option, " <>
      "input and log state live in the Port GenServer and the Smart Cell.",
  "DOC-1" => "README plus module and function docs, reviewed for length and clarity.",
  "TEST-1" =>
    "Tests are grouped in describe blocks per behaviour, with given/when/then helpers " <>
      "(test/support/serial_case.ex).",
  "UI-1" =>
    "Browser side: baud rate, data bits, parity, stop bits and flow control inputs " <>
      "in the cell header, checked in the Claude desktop browser pane (Chromium).",
  "UI-3" =>
    "Connect calls navigator.serial.requestPort. Checked in the Claude desktop browser " <>
      "pane with a mocked navigator.serial, not yet with a real device.",
  "UI-4" =>
    "The USB filter is passed as requestPort({filters}) and the options as " <>
      "port.open({baudRate, dataBits, stopBits, parity, flowControl}). Checked in the " <>
      "Claude desktop browser pane with a mocked navigator.serial.",
  "UI-12" =>
    "Browser side: Disconnect cancels the reader, releases the writer and closes the " <>
      "port. Checked with a mocked SerialPort that refuses to close locked streams.",
  "UI-13" =>
    "Browser side: read errors are reported and reading resumes on the new readable " <>
      "stream; a lost device is reported and disconnects. Checked with a mocked SerialPort.",
  "UI-15" =>
    "Header, inputs and colors follow kino_db's Smart Cells (shared with " <>
      "kino_web_bluetooth). Compared visually with screenshots, not yet inside Livebook.",
  "API-1" =>
    "UI features and their API: connected status and port info (connected?/1, info/1), " <>
      "received data (subscribe/1, stream/1, lines/1), sending (write/3, write_async/2), " <>
      "disconnect (disconnect/1). Text/hex display and clearing are views of the same " <>
      "data. Only picking a port needs the UI."
}
