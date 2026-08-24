# FAQ

## Does it support every wireless headset?

No project can guarantee that. The general `WindowsEndpoint` mode works when Windows exposes a useful physical connection state. AutoSwitch fails closed when it cannot observe a safe signal.

## Why is the Logitech PRO X family special?

Its endpoint can remain `Active` while the headset is physically off, so endpoint state alone cannot distinguish ON/OFF. The project therefore has a G HUB-specific fallback for PRO X, PRO X 2 and PRO X Wireless.

## Does the SteelSeries Arctis Nova 5/5X need its software?

No. AutoSwitch reads the receiver's physical state over HID, so no SteelSeries GG is required.

## Does AutoSwitch run as administrator?

Normal runtime does not need to. Toggling Audio Enhancements launches a narrowly scoped elevated helper and asks for UAC.

## Can I copy config.json to another PC?

No. Windows Item IDs are machine-local.

## Is the G HUB WebSocket official?

No. It is reverse-engineered and may change in future G HUB releases.

## Is Spanish documentation available?

Yes. Start at [[Inicio]].
