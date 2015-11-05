![starscream](https://raw.githubusercontent.com/daltoniam/starscream/assets/starscream.jpg)

Starscream is a conforming WebSocket ([RFC 6455](http://tools.ietf.org/html/rfc6455)) client library in Swift for iOS and OSX.

It's Objective-C counter part can be found here: [Jetfire](https://github.com/acmacalister/jetfire)

This is written Swift 2. (the latest). If you need older legecy support checkout the Swift-1.2 branch [here](https://github.com/daltoniam/Starscream/tree/swift-1.2).

## Features

- Conforms to all of the base [Autobahn test suite](http://autobahn.ws/testsuite/).
- Nonblocking. Everything happens in the background, thanks to GCD.
- Simple delegate pattern design.
- TLS/WSS support.
- Simple concise codebase at just a few hundred LOC.

## Example

First thing is to import the framework. See the Installation instructions on how to add the framework to your project.

```swift
import Starscream
```

Once imported, you can open a connection to your WebSocket server. Note that `socket` is probably best as a property, so your delegate can stick around.

```swift
var socket = WebSocket(url: NSURL(string: "ws://localhost:8080/")!)
socket.delegate = self
socket.connect()
```

After you are connected, there are some delegate methods that we need to implement.

### websocketDidConnect

websocketDidConnect is called as soon as the client connects to the server.

```swift
func websocketDidConnect(socket: WebSocket) {
    println("websocket is connected")
}
```

### websocketDidDisconnect

websocketDidDisconnect is called as soon as the client is disconnected from the server.

```swift
func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
	println("websocket is disconnected: \(error?.localizedDescription)")
}
```

### websocketDidReceiveMessage

websocketDidReceiveMessage is called when the client gets a text frame from the connection.

```swift
func websocketDidReceiveMessage(socket: WebSocket, text: String) {
	println("got some text: \(text)")
}
```

### websocketDidReceiveData

websocketDidReceiveData is called when the client gets a binary frame from the connection.

```swift
func websocketDidReceiveData(socket: WebSocket, data: NSData) {
	println("got some data: \(data.length)")
}
```

### Optional: websocketDidReceivePong *(required protocol: WebSocketPongDelegate)*

websocketDidReceivePong is called when the client gets a pong response from the connection. You need to implement the WebSocketPongDelegate protocol and set an additional delegate, eg: ` socket.pongDelegate = self`

```swift
func websocketDidReceivePong(socket: WebSocket) {
	println("Got pong!")
}
```

Or you can use closures.

```swift
var socket = WebSocket(url: NSURL(string: "ws://localhost:8080/")!)
//websocketDidConnect
socket.onConnect = {
    println("websocket is connected")
}
//websocketDidDisconnect
socket.onDisconnect = { (error: NSError?) in
    println("websocket is disconnected: \(error?.localizedDescription)")
}
//websocketDidReceiveMessage
socket.onText = { (text: String) in
    println("got some text: \(text)")
}
//websocketDidReceiveData
socket.onData = { (data: NSData) in
    println("got some data: \(data.length)")
}
//you could do onPong as well.
socket.connect()
```


## The delegate methods give you a simple way to handle data from the server, but how do you send data?

### writeData

The writeData method gives you a simple way to send `NSData` (binary) data to the server.

```swift
self.socket.writeData(data) //write some NSData over the socket!
```

### writeString

The writeString method is the same as writeData, but sends text/string.

```swift
self.socket.writeString("Hi Server!") //example on how to write text over the socket!
```

### writePing

The writePing method is the same as writeData, but sends a ping control frame.

```swift
self.socket.writePing(NSData()) //example on how to write a ping control frame over the socket!
```

### disconnect

The disconnect method does what you would expect and closes the socket.

```swift
self.socket.disconnect()
```

### isConnected

Returns if the socket is connected or not.

```swift
if self.socket.isConnected {
  // do cool stuff.
}
```

### Custom Headers

You can also override the default websocket headers with your own custom ones like so:

```swift
socket.headers["Sec-WebSocket-Protocol"] = "someother protocols"
socket.headers["Sec-WebSocket-Version"] = "14"
socket.headers["My-Awesome-Header"] = "Everything is Awesome!"
```

### Protocols

If you need to specify a protocol, simple add it to the init:

```swift
//chat and superchat are the example protocols here
var socket = WebSocket(url: NSURL(string: "ws://localhost:8080/")!, protocols: ["chat","superchat"])
socket.delegate = self
socket.connect()
```

### Self Signed SSL and VOIP

There are a couple of other properties that modify the stream:

```swift
var socket = WebSocket(url: NSURL(string: "ws://localhost:8080/")!, protocols: ["chat","superchat"])

//set this if you are planning on using the socket in a VOIP background setting (using the background VOIP service).
socket.voipEnabled = true

//set this you want to ignore SSL cert validation, so a self signed SSL certificate can be used.
socket.selfSignedSSL = true
```

### SSL Pinning

SSL Pinning is also supported in Starscream. 

```swift
var socket = WebSocket(url: NSURL(string: "ws://localhost:8080/")!, protocols: ["chat","superchat"])
let data = ... //load your certificate from disk
socket.security = SSLSecurity(certs: [SSLCert(data: data)], usePublicKeys: true)
//socket.security = SSLSecurity() //uses the .cer files in your app's bundle
```
You load either a `NSData` blob of your certificate or you can use a `SecKeyRef` if you have a public key you want to use. The `usePublicKeys` bool is whether to use the certificates for validation or the public keys. The public keys will be extracted from the certificates automatically if `usePublicKeys` is choosen.

### Custom Queue

A custom queue can be specified when delegate methods are called. By default `dispatch_get_main_queue` is used, thus making all delegate methods calls run on the main thread. It is important to note that all WebSocket processing is done on a background thread, only the delegate method calls are changed when modifying the queue. The actual processing is always on a background thread and will not pause your app.

```swift
var socket = WebSocket(url: NSURL(string: "ws://localhost:8080/")!, protocols: ["chat","superchat"])
//create a custom queue
socket.queue = dispatch_queue_create("com.vluxe.starscream.myapp", nil)
```

## Example Project

Check out the SimpleTest project in the examples directory to see how to setup a simple connection to a WebSocket server.

## Requirements

Starscream works with iOS 7/OSX 10.9 or above. It is recommended to use iOS 8/10.10 or above for Cocoapods/framework support. To use Starscream with a project targeting iOS 7, you must include all Swift files directly in your project.

## Installation

### Cocoapods

Check out [Get Started](http://cocoapods.org/) tab on [cocoapods.org](http://cocoapods.org/).

To use Starscream in your project add the following 'Podfile' to your project

	source 'https://github.com/CocoaPods/Specs.git'
	platform :ios, '8.0'
	use_frameworks!

	pod 'Starscream', '~> 1.0.0'

Then run:

    pod install

### Carthage

Check out the [Carthage](https://github.com/Carthage/Carthage) docs on how to add a install. The `Starscream` framework is already setup with shared schemes.

[Carthage Install](https://github.com/Carthage/Carthage#adding-frameworks-to-an-application)

You can install Carthage with [Homebrew](http://brew.sh/) using the following command:

```bash
$ brew update
$ brew install carthage
```

To integrate Starscream into your Xcode project using Carthage, specify it in your `Cartfile`:

```
github "daltoniam/Starscream" >= 1.0.0
```

### Rogue

First see the [installation docs](https://github.com/acmacalister/Rogue) for how to install Rogue.

To install Starscream run the command below in the directory you created the rogue file.

```
rogue add https://github.com/daltoniam/starscream
```

Next open the `libs` folder and add the `Starscream.xcodeproj` to your Xcode project. Once that is complete, in your "Build Phases" add the `Starscream.framework` to your "Link Binary with Libraries" phase. Make sure to add the `libs` folder to your `.gitignore` file.

### Other

Simply grab the framework (either via git submodule or another package manager).

Add the `Starscream.xcodeproj` to your Xcode project. Once that is complete, in your "Build Phases" add the `Starscream.framework` to your "Link Binary with Libraries" phase.

### Add Copy Frameworks Phase

If you are running this in an OSX app or on a physical iOS device you will need to make sure you add the `Starscream.framework` to be included in your app bundle. To do this, in Xcode, navigate to the target configuration window by clicking on the blue project icon, and selecting the application target under the "Targets" heading in the sidebar. In the tab bar at the top of that window, open the "Build Phases" panel. Expand the "Link Binary with Libraries" group, and add `Starscream.framework`. Click on the + button at the top left of the panel and select "New Copy Files Phase". Rename this new phase to "Copy Frameworks", set the "Destination" to "Frameworks", and add `Starscream.framework` respectively.

## TODOs

- [ ] WatchOS
- [ ] Add Unit Tests

## License

Starscream is licensed under the Apache v2 License.

## Contact

### Dalton Cherry
* https://github.com/daltoniam
* http://twitter.com/daltoniam
* http://daltoniam.com

### Austin Cherry ###
* https://github.com/acmacalister
* http://twitter.com/acmacalister
* http://austincherry.me
