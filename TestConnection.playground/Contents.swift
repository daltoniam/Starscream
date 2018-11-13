import Starscream
import PlaygroundSupport

PlaygroundPage.current.needsIndefiniteExecution = true

let websocket = WebSocket(request: URLRequest(url: URL(string: "ws://echo.websocket.org")!), stream: NetworkStream())

websocket.onConnect = {
  print("connected")
  
  websocket.write(string: "Hello")
}

websocket.onDisconnect = { error in
  print("error:", error)
}

websocket.onText = { text in
  print(text)
}

websocket.connect()
