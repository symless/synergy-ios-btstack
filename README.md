# Synergy for iOS

This client is an update and partial rewrite of "iSynergyClient," an unfortunately abandoned project. 

It has basic support for iOS 13. Many things are still unfinished.

This package used to depend on hid-support, mouse-support(?), apparently some bluetooth keyboard tweak, and other things i'm sure I haven't found yet. 

I've added hid-support as a submodule to this project, (partially) fixed it for iOS 13, and added a very basic cursor to it.

Sensitivity is rough due to a high pixel ratio.

This package is avaliable in .deb form on the releases page here, or on https://repo.openpack.io/

* Install a Synergy server on your computer as normal
* Configure server to have one additional screen (client) called "iPhone" (or the hostname)
* Start SynergyClient on your iOS device
* Enter IP-Address or name of your Mac/PC in "Server Address"
* Enter "iPhone" (or the hostname) as "Client Name"
* Tap the ON switch and move mouse over from Mac/PC
* Done. Your mouse is on your device!
