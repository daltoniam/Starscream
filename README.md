![starscream](https://raw.githubusercontent.com/daltoniam/starscream/assets/starscream.jpg)

Starscream is a conforming WebSocket ([RFC 6455](http://tools.ietf.org/html/rfc6455)) client library in Swift for iOS and OSX.

It's Objective-C counter part can be found here: [Jetfire](https://github.com/acmacalister/jetfire)

## Features

- Conforms to all of the base [Autobahn test suite](http://autobahn.ws/testsuite/).
- Nonblocking. Everything happens in the background, thanks to GCD.
- TLS/WSS support.
- Simple concise codebase at just a few hundred LOC.

## Swift 2.3

See release/tag 1.1.4 for Swift 2.3 support.

## Example

First thing is to import the framework. See the Installation instructions on how to add the framework to your project.

```swift
import Starscream
```

Once imported, you can open a connection to your WebSocket server. Note that `socket` is probably best as a property, so it doesn't get deallocated right after being setup.

```swift
socket = WebSocket(url: URL(string: "ws://localhost:8080/")!)
socket.delegate = self
socket.connect()
```

After you are connected, there are some delegate methods that we need to implement.

### websocketDidConnect

websocketDidConnect is called as soon as the client connects to the server.

```swift
func websocketDidConnect(socket: WebSocket) {
    print("websocket is connected")
}
```

### websocketDidDisconnect

websocketDidDisconnect is called as soon as the client is disconnected from the server.

```swift
func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
	print("websocket is disconnected: \(error?.localizedDescription)")
}
```

### websocketDidReceiveMessage

websocketDidReceiveMessage is called when the client gets a text frame from the connection.

```swift
func websocketDidReceiveMessage(socket: WebSocket, text: String) {
	print("got some text: \(text)")
}
```

### websocketDidReceiveData

websocketDidReceiveData is called when the client gets a binary frame from the connection.

```swift
func websocketDidReceiveData(socket: WebSocket, data: Data) {
	print("got some data: \(data.count)")
}
```

### Optional: websocketDidReceivePong *(required protocol: WebSocketPongDelegate)*

websocketDidReceivePong is called when the client gets a pong response from the connection. You need to implement the WebSocketPongDelegate protocol and set an additional delegate, eg: ` socket.pongDelegate = self`

```swift
func websocketDidReceivePong(socket: WebSocket, data: Data?) {
	print("Got pong! Maybe some data: \(data?.count)")
}
```

Or you can use closures.

```swift
socket = WebSocket(url: URL(string: "ws://localhost:8080/")!)
//websocketDidConnect
socket.onConnect = {
    print("websocket is connected")
}
//websocketDidDisconnect
socket.onDisconnect = { (error: NSError?) in
    print("websocket is disconnected: \(error?.localizedDescription)")
}
//websocketDidReceiveMessage
socket.onText = { (text: String) in
    print("got some text: \(text)")
}
//websocketDidReceiveData
socket.onData = { (data: Data) in
    print("got some data: \(data.count)")
}
//you could do onPong as well.
socket.connect()
```

One more: you can listen to socket connection and disconnection via notifications. Starscream posts `WebsocketDidConnectNotification` and `WebsocketDidDisconnectNotification`. You can find an `NSError` that caused the disconection by accessing `WebsocketDisconnectionErrorKeyName` on notification `userInfo`.


## The delegate methods give you a simple way to handle data from the server, but how do you send data?

### write a binary frame

The writeData method gives you a simple way to send `Data` (binary) data to the server.

```swift
socket.write(data: data) //write some Data over the socket!
```

### write a string frame

The writeString method is the same as writeData, but sends text/string.

```swift
socket.write(string: "Hi Server!") //example on how to write text over the socket!
```

### write a ping frame

The writePing method is the same as write, but sends a ping control frame.

```swift
socket.write(ping: Data()) //example on how to write a ping control frame over the socket!
```

### disconnect

The disconnect method does what you would expect and closes the socket.

```swift
socket.disconnect()
```

### isConnected

Returns if the socket is connected or not.

```swift
if socket.isConnected {
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
socket = WebSocket(url: URL(string: "ws://localhost:8080/")!, protocols: ["chat","superchat"])
socket.delegate = self
socket.connect()
```

### Self Signed SSL and VOIP

There are a couple of other properties that modify the stream:

```swift
socket = WebSocket(url: URL(string: "ws://localhost:8080/")!, protocols: ["chat","superchat"])

//set this if you are planning on using the socket in a VOIP background setting (using the background VOIP service).
socket.voipEnabled = true

//set this you want to ignore SSL cert validation, so a self signed SSL certificate can be used.
socket.disableSSLCertValidation = true
```

### SSL Pinning

SSL Pinning is also supported in Starscream. 

```swift
socket = WebSocket(url: URL(string: "ws://localhost:8080/")!, protocols: ["chat","superchat"])
let data = ... //load your certificate from disk
socket.security = SSLSecurity(certs: [SSLCert(data: data)], usePublicKeys: true)
//socket.security = SSLSecurity() //uses the .cer files in your app's bundle
```
You load either a `Data` blob of your certificate or you can use a `SecKeyRef` if you have a public key you want to use. The `usePublicKeys` bool is whether to use the certificates for validation or the public keys. The public keys will be extracted from the certificates automatically if `usePublicKeys` is choosen.

### Custom Queue

A custom queue can be specified when delegate methods are called. By default `DispatchQueue.main` is used, thus making all delegate methods calls run on the main thread. It is important to note that all WebSocket processing is done on a background thread, only the delegate method calls are changed when modifying the queue. The actual processing is always on a background thread and will not pause your app.

```swift
socket = WebSocket(url: URL(string: "ws://localhost:8080/")!, protocols: ["chat","superchat"])
//create a custom queue
socket.callbackQueue = DispatchQueue(label: "com.vluxe.starscream.myapp")
```

## Example Project

Check out the SimpleTest project in the examples directory to see how to setup a simple connection to a WebSocket server.

## Requirements

Starscream works with iOS 7/OSX 10.9 or above. It is recommended to use iOS 8/10.10 or above for CocoaPods/framework support. To use Starscream with a project targeting iOS 7, you must include all Swift files directly in your project.

## Installation

### CocoaPods

Check out [Get Started](http://cocoapods.org/) tab on [cocoapods.org](http://cocoapods.org/).

To use Starscream in your project add the following 'Podfile' to your project

	source 'https://github.com/CocoaPods/Specs.git'
	platform :ios, '9.0'
	use_frameworks!

	pod 'Starscream', '~> 2.0.0'

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
github "daltoniam/Starscream" >= 2.0.0
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

- [ ] WatchOS?
- [ ] Linux Support?
- [ ] Add Unit Tests - Local Swift websocket server

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
