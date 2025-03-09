---
title: 'Websockets Code Zoom: Receiving Client Handshake'
description: 'In this blog post, we will be looking at code that parses client handshake packet.'
pubDate: 'Mar 09 2025'
heroImage: '/websockets-code-zoom-03.jpg'
---

In this blog post, we will be looking at code that parses client handshake
packet. I'm implementing the code from the
[RFC6455](https://datatracker.ietf.org/doc/html/rfc6455#section-1.3)
specification.

I'll start with the general program structure and how things work in code.

### Structure

We'll have a main loop that opens a TCP listener on port `8080`. Whenever a
client comes by, a new `goroutine` will be kicked to handle this client. In
simple terms, this means we can handle multiple clients concurrently.

```go
func main() {
  server, err := net.Listen("tcp", ":8080")
  if err != nil {
    panic(
      fmt.Errorf("Failed to listen: %s", err),
    )
  }

  for {
    conn, err := server.Accept()
    if err != nil {
      panic(
        fmt.Errorf("Failed to accept: %s", err),
      )
    }

    go initiateConnection(conn)
  }
}
```

So far, nothing fancy happens. In `initiateConnection()` we'll listen for client
packets that are sent. Currently, we just have an open TCP connection, not a
single byte has been transfered so far.

To read bytes coming from client, we need to have a place to store them, right?
🤔 Yes, so we'll have a buffer for coming requests. The choice of the buffer
size here is arbitrary, a good enough buffer size would be the maximum chunk
that the network can transfer
([Maximum Transmission Unit](https://www.cloudflare.com/learning/network-layer/what-is-mtu/)),
which is 1500 bytes. I'll stick with the arbitarary value for now.

```go
func readMessage(socket net.Conn) ([]byte, error) {
  buffer := make([]byte, 2048)
  n, err := socket.Read(buffer)
  if err != nil {
    return nil, err
  }

  return buffer[:n], nil
}
```

What's `buffer[:n]` doing? good question! If you're carrying one apple, do you
really need a backpack to hold it? probably no. Same here, we don't need to keep
the 2kb buffer allocated if we just have a message of 20 bytes.

Now, back to `initiateConnection()` this is the general idea of receiving `TCP` packets
from our clients:

```go
func initiateConnection(socket net.Conn) {
  message, err := readMessage(socket)
  if err != nil { 
    fmt.Printf("Failed to read handshake: %v", err)
    return
  }
  
  websocketHandshake, err := http_parser.Parse(message)
  // ...
  // ... handshaking code ... to be discussed ...
  // ...

  for {
    // Read incoming packets after handshake.
    message, err = readMessage(socket)
    if err != nil {
      fmt.Printf("Failed to read: %v", err)
      return
    }

    fmt.Printf("Received %d bytes\n", len(message))
  }

}
```
We'll be discussing `websocketHandshake, err := http_parser.Parse(message)` next.

### HTTP | First things first

When the client initiates a Websocket connection, it first sends an HTTP upgrade
request, so we'll need to parse this request first.

Since I'm writing code for just a Websocket server, I'm not interested in HTTP details,
so I'll make life easy for myself and do just the bare minumum for HTTP. You can find the full code [here](https://github.com/shakram02/nony-chat/tree/f8337df99e0030d09d8ca652ed95102dbd02f6d2/adapters/http).

To parse the HTTP request, we split it by `\r\n` to get all lines in the request, remember that `HTTP` is
a text based protocol.

The very first line in the request is formally called the `Request Line` [RFC2616](https://datatracker.ietf.org/doc/html/rfc2616#page-35) which comes followed by headers.

Our HTTP request from the client MUST satisfy the following, as per the Websocket [RFC spec](https://datatracker.ietf.org/doc/html/rfc6455#page-17):

1. MUST be a valid HTTP request
2. The method MUST be GET, and the HTTP version MUST be at least 1.1
3. The "Request-URI" part MUST be a relative URI or a full `ws://`, `wss://` URI or a full HTTP/S URI
4. Contain a `Host` header field
5. Contain an `Upgrade` header field whose value MUST include the "websocket" keyword.
6. Contain a `Connection` header field whose value MUST include the "Upgrade" token.
7. The request MUST include a header field with the name `Sec-WebSocket-Key`.
8. If the request is coming from a browser, then it must include the `Origin` header, if you're not expecting non-browser clients, then you must reject requests without an `Origin` header.
9. The request MUST include a header field with the name `Sec-WebSocket-Version`. The value of this header field MUST be 13.

The following is the entry point for parsing the HTTP request
```go

func Parse(request []byte) (WebsocketHandshake, error) {
  requestString := string(request)

  httpRequestParts := strings.Split(requestString, "\r\n")
  if len(httpRequestParts) == 0 {
    return WebsocketHandshake{}, fmt.Errorf("Invalid HTTP request: %s", requestString)
  }

  requestLine, err := parseHandshakeRequestLine(httpRequestParts[0])
  if err != nil {
    return WebsocketHandshake{}, fmt.Errorf("Invalid request line: %s", httpRequestParts[0])
  }

  headerParts := httpRequestParts[1:]
  headers, err := parseHandshakeHeaders(headerParts)
  if err != nil {
    return WebsocketHandshake{}, fmt.Errorf("Invalid headers: %s", err)
  }

  return WebsocketHandshake{
    RequestLine: requestLine,
    Headers:     headers,
  }, nil
}
```

With `parseHandshakeRequestLine` just parsing the Request Line and validating its requirements, and `parseHandshakeHeaders` validating headers. Full code is [here](https://github.com/shakram02/nony-chat/blob/f8337df99e0030d09d8ca652ed95102dbd02f6d2/adapters/http/parser/parser.go) along with [tests](https://github.com/shakram02/nony-chat/blob/f8337df99e0030d09d8ca652ed95102dbd02f6d2/adapters/http/parser/parser_test.go).

After parsing the request I keep the following information for completing the handshake process. I use the values here to build the handshake response. but that's the topic for the next post isA.
```go
type HandshakeHeaders struct {
	//The handshake MUST be a valid HTTP request as specified by [RFC2616].
	// https://datatracker.ietf.org/doc/html/rfc2616#page-128
	// The Host field value MUST represent
	// the naming authority of the origin server or gateway given by the
	// original URL. This allows the origin server or gateway to
	// differentiate between internally-ambiguous URLs, such as the root "/"
	// URL of a server for multiple host names on a single IP address.
	Host string
	// An |Upgrade| header field containing the value "websocket",
	// treated as an ASCII case-insensitive value.
	Upgrade string
	//  The request MUST contain a |Connection| header field whose value
	// MUST include the "Upgrade" token.
	Connection string
	// The request MUST include a header field with the name
	// |Sec-WebSocket-Key|.  The value of this header field MUST be a
	// nonce consisting of a randomly selected 16-byte value that has
	// been base64-encoded (see Section 4 of [RFC4648]).  The nonce
	// MUST be selected randomly for each connection.
	SecWebSocketKey string
}

```

I hope you find this post useful, feel free to reach out for any comments/questions. Happy coding 📜