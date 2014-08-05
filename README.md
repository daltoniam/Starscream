starscream
==========

WebSocket [RFC 6455](http://tools.ietf.org/html/rfc6455) client library in swift for iOS and OSX.

starscream conforms to all of the base [Autobahn test suite](http://autobahn.ws/testsuite/). The library is very simple and only a few hundred lines of code, but fully featured. It runs completely on a background thread, so processing will never block the main thread. 

starscream also has a Objective-C counter part here: [jetfire](https://github.com/acmacalister/jetfire)


## Example ##

Open a connection to your websocket server. `socket` is a property, so it can stick around.

```swift
var socket = Websocket(url: NSURL.URLWithString("ws://localhost:8080"))
socket.delegate = self
socket.connect()
```

Now for the delegate methods.

```swift
func websocketDidConnect() {
    println("websocket is connected")
}
func websocketDidDisconnect(error: NSError?) {
	println("websocket is disconnected: \(error!.localizedDescription)")
}
func websocketDidWriteError(error: NSError?) {
    println("wez got an error from the websocket: \(error!.localizedDescription)")
}
func websocketDidReceiveMessage(text: String) {
	println("got some text: \(text)")
	//self.socket.writeString(text) //example on how to write a string the socket
}
func websocketDidReceiveData(data: NSData) {
	println("got some data: \(data.length)")
    //self.socket.writeData(data) //example on how to write binary data to the socket
}
```

## Requirements ##

starscream requires at least iOS 7/OSX 10.10 or above.


## License ##

starscream is license under the Apache License.

## Contact ##

### Dalton Cherry ###
* https://github.com/daltoniam
* http://twitter.com/daltoniam
* http://daltoniam.com