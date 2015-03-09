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

First thing is to import the framework. See the Installation instructions on how to add the framework to your project.

```swift
import Starscream
```

Once imported, you can open a connection to your WebSocket server. Note that `socket` is probably best as a property, so your delegate can stick around.

```swift
var socket = WebSocket(url: NSURL(scheme: "ws", host: "localhost:8080", path: "/"))
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
	println("websocket is disconnected: \(error!.localizedDescription)")
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
var socket = WebSocket(url: NSURL(scheme: "ws", host: "localhost:8080", path: "/"), protocols: ["chat","superchat"])
socket.delegate = self
socket.connect()
```

### Self Signed SSL and VOIP

There are a couple of other properties that modify the stream:

```swift
var socket = WebSocket(url: NSURL(scheme: "ws", host: "localhost:8080", path: "/"), protocols: ["chat","superchat"])

//set this if you are planning on using the socket in a VOIP background setting (using the background VOIP service).
socket.voipEnabled = true

//set this you want to ignore SSL cert validation, so a self signed SSL certificate can be used.
socket.selfSignedSSL = true
```

### Custom Queue

A custom queue can be specified when delegate methods are called. By default `dispatch_get_main_queue` is used, thus making all delegate methods calls run on the main thread. It is important to note that all WebSocket processing is done on a background thread, only the delegate method calls are changed when modifying the queue. The actual processing is always on a background thread and will not pause your app.

```swift
var socket = WebSocket(url: NSURL(scheme: "ws", host: "localhost:8080", path: "/"), protocols: ["chat","superchat"])
//create a custom queue
socket.queue = dispatch_queue_create("com.vluxe.starscream.myapp", nil)
```

## Example Project

Check out the SimpleTest project in the examples directory to see how to setup a simple connection to a WebSocket server.

## Requirements

Starscream works with iOS 7/OSX 10.9 or above. It is recommended to use iOS 8/10.10 or above for Cocoapods/framework support.

## Installation

### [CocoaPods](http://cocoapods.org/)
At this time, Cocoapods support for Swift frameworks is supported in a [pre-release](http://blog.cocoapods.org/Pod-Authors-Guide-to-CocoaPods-Frameworks/).

To use Starscream in your project add the following 'Podfile' to your project

    source 'https://github.com/CocoaPods/Specs.git'

    xcodeproj 'YourProjectName.xcodeproj'
    platform :ios, '8.0'

    pod 'Starscream', :git => "https://github.com/daltoniam/starscream.git", :tag => "0.9.1"

    target 'YourProjectNameTests' do
        pod 'Starscream', :git => "https://github.com/daltoniam/starscream.git", :tag => "0.9.1"
    end

Then run:

    pod install

#### Updating the Cocoapod
You can validate Starscream.podspec using:

    pod spec lint Starscream.podspec

This should be tested with a sample project before releasing it. This can be done by adding the following line to a ```Podfile```:

    pod 'Starscream', :git => 'https://github.com/username/starscream.git'

Then run:

    pod install

If all goes well you are ready to release. First, create a tag and push:

    git tag 'version'
    git push --tags

Once the tag is available you can send the library to the Specs repo. For this you'll have to follow the instructions in [Getting Setup with Trunk](http://guides.cocoapods.org/making/getting-setup-with-trunk.html).

    pod trunk push Starscream.podspec

### Carthage

Check out the [Carthage](https://github.com/Carthage/Carthage) docs on how to add a install. The `Starscream` framework is already setup with shared schemes.

[Carthage Install](https://github.com/Carthage/Carthage#adding-frameworks-to-an-application)

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

If you are running this in an OSX app or on a physical iOS device you will need to make sure you add the `Starscream.framework` or `StarscreamOSX.framework` to be included in your app bundle. To do this, in Xcode, navigate to the target configuration window by clicking on the blue project icon, and selecting the application target under the "Targets" heading in the sidebar. In the tab bar at the top of that window, open the "Build Phases" panel. Expand the "Link Binary with Libraries" group, and add `Starscream.framework` or `StarscreamOSX.framework` depending on if you are building an iOS or OSX app. Click on the + button at the top left of the panel and select "New Copy Files Phase". Rename this new phase to "Copy Frameworks", set the "Destination" to "Frameworks", and add `Starscream.framework` or `StarscreamOSX.framework` respectively.

## TODOs

- [ ] Complete Docs
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
