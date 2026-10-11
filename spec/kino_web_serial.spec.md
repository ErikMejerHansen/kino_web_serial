# EARS
## Syntax: While <optional pre-condition>, when <optional trigger>, the <system name> shall <system response>
## Examples
Ubiquitous requirements
Ubiquitous requirements are always active (so there is no EARS keyword)

The <system name> shall <system response>

Example: The mobile phone shall have a mass of less than XX grams.

State driven requirements
State driven requirements are active as long as the specified state remains true and are denoted by the keyword While.

While <precondition(s)>, the <system name> shall <system response>

Example: While there is no card in the ATM, the ATM shall display “insert card to begin”.

Event driven requirements
Event driven requirements specify how a system must respond when a triggering event occurs and are denoted by the keyword When.

When <trigger>, the <system name> shall <system response>

Example: When “mute” is selected, the laptop shall suppress all audio output.

Optional feature requirements
Optional feature requirements apply in products or systems that include the specified feature and are denoted by the keyword Where.

Where <feature is included>, the <system name> shall <system response>

Example: Where the car has a sunroof, the car shall have a sunroof control panel on the driver door.

Unwanted behaviour requirements
Unwanted behaviour requirements are used to specify the required system response to undesired situations and are denoted by the keywords If and Then.

If <trigger>, then the <system name> shall <system response>

Example: If an invalid credit card number is entered, then the website shall display “please re-enter credit card details”.

Complex requirements
The simple building blocks of the EARS patterns described above can be combined to specify requirements for richer system behaviour. Requirements that include more than one EARS keyword are called Complex requirements.

While <precondition(s)>, When <trigger>, the <system name> shall <system response>

# Requirement IDs

Every requirement is a list item starting with a unique ID, like
`- [UI-4] The KinoWebSerial UI shall ...`. Tests and reviews refer
to requirements by ID, so:

- To add a requirement, give it the next free ID in its section.
- To reword a requirement without changing its meaning, keep its ID.
- To change what a requirement means, give it a new ID. Its old tests
  and reviews then no longer count, until they are updated.
- To remove a requirement, delete it. Never reuse its ID.

Run `mix spec` to see which requirements are implemented, in
[STATUS.md](STATUS.md).

# Spec

## Architecture
- [ARCH-1] The hex package name for this KinoSmartCell shall be kino_web_serial
- [ARCH-2] The top level namespace for this project shall be KinoWebSerial

- [ARCH-3] The KinoWebSerial shall have a UI for use in a Livebook
- [ARCH-4] The KinoWebSerial shall have a programmatic API

- [ARCH-5] The KinoWebSerial shall have a GenServer per serial port
- [ARCH-6] The KinoWebSerial shall keep state in Elixir except where strictly needed

## Documentation
- [DOC-1] The KinoWebSerial shall have concise and easy to read documentation

## Testing
- [TEST-1] The KinoWebSerial shall have easy to read tests in a BDD style

## UI
- [UI-1] The KinoWebSerial UI shall show input fields for the serial connection options: baud rate, data bits, parity, stop bits and flow control
- [UI-2] The KinoWebSerial UI shall show input fields that allow filtering the ports offered by USB vendor and product ID
- [UI-3] The KinoWebSerial UI shall show a button that triggers the browser's serial port selector
- [UI-4] The KinoWebSerial UI shall pass the user provided connection options and filters to the browser's Web Serial functionality
- [UI-5] The KinoWebSerial UI shall show if a serial port is connected
- [UI-6] The KinoWebSerial UI shall show information about the connected serial port
- [UI-7] The KinoWebSerial UI shall show the data received from the serial port
- [UI-8] The KinoWebSerial UI shall show UI to allow sending data to the serial port as text or hex, with an optional line ending
- [UI-9] The KinoWebSerial UI shall show the data sent to the serial port
- [UI-10] The KinoWebSerial UI shall allow showing the sent and received data as text or as hex
- [UI-11] The KinoWebSerial UI shall allow clearing the shown data
- [UI-12] When the user clicks Disconnect, the KinoWebSerial UI shall close the serial port
- [UI-13] If reading from the serial port fails, then the KinoWebSerial UI shall show the error
- [UI-14] The KinoWebSerial UI shall persist user input as part of the Livebook
- [UI-15] The KinoWebSerial UI shall match the UX/UI of the official Kino Smart Cells

## Programmatic API
- [API-1] The KinoWebSerial API shall have the same functionality as the UI except where the browser requires direct user input
- [API-2] The KinoWebSerial API shall allow subscribing to async data received by the GenServer representing the serial port
- [API-3] The KinoWebSerial API shall allow sync and async writes to the GenServer representing the serial port
- [API-4] The KinoWebSerial API shall allow setting the DTR, RTS and break control signals and reading the CTS, DSR, DCD and RI status signals
- [API-5] The KinoWebSerial API shall allow consuming received data as a stream of chunks or of lines
