![starscream](http://limitedtoy.com/wp-content/uploads/2014/09/transformers-starscream-wallpaperstarscream-transformers-2-wallpaper---332913-pnx7lnff.jpg)

Starscream is a conforming WebSocket ([RFC 6455](http://tools.ietf.org/html/rfc6455)) client library in Swift for iOS and OSX.

It's Objective-C counter part can be found here: [Jetfire](https://github.com/acmacalister/jetfire)


## Features

- Conforms to all of the base [Autobahn test suite](http://autobahn.ws/testsuite/).
- Nonblocking. Everything happens in the background, thanks to GCD.
- Simple delegate pattern design.
- TLS/WSS support.
- Simple concise codebase at just a few hundred LOC.

## Example

First thing is to import the framework. See the Installation instructions, on how to add the framework to your project.

```swift
import Starscream
```

Once imported, you can open a connection to your websocket server. Note that `socket` is probably best as a property, so your delegate can stick around.

```swift
var socket = Websocket(url: NSURL(scheme: "ws", host: "localhost:8080", path: "/"))
socket.delegate = self
socket.connect()
```

After you are connected, we some delegate methods we need to implement.

### websocketDidConnect

websocketDidConnect is called as soon as the client connects to the server.

```swift
func websocketDidConnect() {
    println("websocket is connected")
}
```

### websocketDidDisconnect

websocketDidDisconnect is called as soon as the client is disconnected from the server.

```swift
func websocketDidDisconnect(error: NSError?) {
	println("websocket is disconnected: \(error!.localizedDescription)")
}
```

### websocketDidWriteError

websocketDidWriteError is called when the client gets an error on websocket connection.

```swift
func websocketDidWriteError(error: NSError?) {
    println("wez got an error from the websocket: \(error!.localizedDescription)")
}
```

### websocketDidReceiveMessage

websocketDidReceiveMessage is called when the client gets a text frame from the connection.

```swift
func websocketDidReceiveMessage(text: String) {
	println("got some text: \(text)")
}
```

### websocketDidReceiveData

websocketDidReceiveData is called when the client gets a binary frame from the connection.

```swift
func websocketDidReceiveData(data: NSData) {
	println("got some data: \(data.length)")
}
```

The delegate methods give you a simple way to handle data from the server, but how do you send data?

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
var socket = Websocket(url: NSURL(scheme: "ws", host: "localhost:8080", path: "/"), protocols: ["chat","superchat"])
socket.delegate = self
socket.connect()
```

## Example Project

Check out the SimpleTest project in the examples directory to see how to setup a simple connection to a websocket server.

## Requirements

Starscream requires at least iOS 7/OSX 10.10 or above.

## Installation

Add the `starscream.xcodeproj` to your Xcode project. Once that is complete, in your "Build Phases" add the `starscream.framework` to your "Link Binary with Libraries" phase.

## TODOs

- [ ] Complete Docs
- [ ] Add Unit Tests
- [ ] Add Swallow Installation Docs

## License

Starscream is licensed under the Apache v2 License.

## Contact

### Dalton Cherry
* https://github.com/daltoniam
* http://twitter.com/daltoniam
* http://daltoniam.com