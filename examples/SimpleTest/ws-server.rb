require 'em-websocket'

EM.run {
  EM::WebSocket.run(:host => "0.0.0.0", :port => 8080) do |ws|
    ws.onopen { |handshake|
      puts "WebSocket connection open"
      puts "origin: #{handshake.origin}"
      puts "headers: #{handshake.headers}"

      ws.send "Hello Client, you connected to #{handshake.path}"
    }

    ws.onerror do |error|
      puts "[error] #{error}"
    end

    ws.onclose { puts "Connection closed" }

    ws.onmessage { |msg|
      puts "Recieved message: #{msg}"
      ws.send "Pong: #{msg}"
    }
  end
}