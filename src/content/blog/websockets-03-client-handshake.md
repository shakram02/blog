---
title: 'Websocket Code Zoom: Receiving Client Handshake'
description: 'In this blog post, we will be looking at code that parses client handshake packet.'
pubDate: 'Mar 10 2025'
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

Now, back to `initiateConnection()` this is the general idea of receiving `TCP`
packets from our clients:

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

We'll be discussing `websocketHandshake, err := http_parser.Parse(message)`
next.

### First things first | HTTP

When the client initiates a Websocket connection, it first sends an HTTP upgrade
request, so we'll need to parse this request first.

Since I'm writing code for just a Websocket server, I'm not interested in HTTP
details, so I'll make life easy for myself and do just the bare minumum for
HTTP. You can find the full code
[here](https://github.com/shakram02/nony-chat/tree/f8337df99e0030d09d8ca652ed95102dbd02f6d2/adapters/http).

To parse the HTTP request, we split it by `\r\n` to get all lines in the
request, remember that `HTTP` is a text based protocol.

The very first line in the request is formally called the `Request Line`
[RFC2616](https://datatracker.ietf.org/doc/html/rfc2616#page-35) which comes
followed by headers.

Our HTTP request from the client MUST satisfy the following, as per the
Websocket [RFC spec](https://datatracker.ietf.org/doc/html/rfc6455#page-17):

1. MUST be a valid HTTP request
2. The method MUST be GET, and the HTTP version MUST be at least 1.1
3. The "Request-URI" part MUST be a relative URI or a full `ws://`, `wss://` URI
   or a full HTTP/S URI
4. Contain a `Host` header field
5. Contain an `Upgrade` header field whose value MUST include the "websocket"
   keyword.
6. Contain a `Connection` header field whose value MUST include the "Upgrade"
   token.
7. The request MUST include a header field with the name `Sec-WebSocket-Key`.
8. If the request is coming from a browser, then it must include the `Origin`
   header, if you're not expecting non-browser clients, then you must reject
   requests without an `Origin` header.
9. The request MUST include a header field with the name
   `Sec-WebSocket-Version`. The value of this header field MUST be 13.

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

### Parsing HTTP Request Line

To parse the HTTP Request Line We should check how it's defined first, which is
documented in the HTTP
[RFC2616](https://datatracker.ietf.org/doc/html/rfc2616#page-35) which dates
back to 1999! Now we know that, we just need the first 3 tokens, and they should
satisfy the following requirements:

- Method -> `GET`
- URI -> any value that starts with a `/` works
- Http Version -> 1.1+ works

```go
func parseHandshakeRequestLine(requestLine string) (HandshakeRequestLine, error) {
	parts := strings.Split(strings.TrimSpace(requestLine), " ")
	if len(parts) < 3 {
		return HandshakeRequestLine{}, fmt.Errorf("Invalid Handshake Request-Line")
	}

	parts = parts[:3] // The handshake has just 3 parts e.g. GET /chat HTTP/1.1
	if parts[0] != "GET" {
		return HandshakeRequestLine{}, fmt.Errorf("Invalid method")
	}

	if parts[1][0] != '/' {
		return HandshakeRequestLine{}, fmt.Errorf("Invalid URI")
	}

	major, minor, ok := http.ParseHTTPVersion(parts[2])
	if !ok {
		return HandshakeRequestLine{}, fmt.Errorf("Invalid Protocol version")
	}

	acceptedVersion := (major == 1 && minor == 1) || (major > 1)
	if !acceptedVersion {
		return HandshakeRequestLine{}, fmt.Errorf("Invalid Protocol version")
	}

	return HandshakeRequestLine{Uri: parts[1]}, nil
}
```

### Parsing HTTP Headers

To validate HTTP headers in the handshake requests we need to parse them first
😬.

`parseHandshakeHeaders` calls `parseHttpHeaders` and
`hasRequiredHanshakeHeaders` functions that have the knits and grits of parsing
and validation logic.

```go
func parseHandshakeHeaders(headerLines []string) (HandshakeHeaders, error) {
	headers := parseHttpHeaders(headerLines)
	if !hasRequiredHanshakeHeaders(headers) {
		return HandshakeHeaders{}, fmt.Errorf("Invalid headers")
	}

	return HandshakeHeaders{
		Host:            headers["Host"],
		Upgrade:         headers["Upgrade"],
		Connection:      headers["Connection"],
		SecWebSocketKey: headers["Sec-WebSocket-Key"],
	}, nil

}
```

Getting to parse HTTP headers is straight forward, by splitting the Header Lines
by `:` to extract the Key and Value present in the headers.

If the `headerLine` is empty then that means that we're done with the header
portion of the `HTTP` requests. If any invalid headers are present, I just skip
them.

```go
func parseHttpHeaders(headerLines []string) map[string]string {
  headers := make(map[string]string)
  for _, line := range headerLines {
    if strings.TrimSpace(line) == "" {
      // Body separator
      break
    }
    splits := strings.Split(line, ": ")

    if len(splits) != 2 {
      // Skip invalid headers
      continue
    }

    key := splits[0]
    value := splits[1]
    headers[key] = value
  }

	return headers
}
```

### Validating HTTP Headers

The way I thought about validating headers was to have a `Map` that has required
values, and empty values if the present value in the HTTP request isn't very
important. So, in the following `requiredHeaders` map, I'm leaving out the
`Host` and `Sec-WebSocket-Key` as empty values because I accept all values
there.

```go
// https://datatracker.ietf.org/doc/html/rfc6455#section-4.1
var requiredHeaders = map[string]string{
	"Host":              "",
	"Upgrade":           "websocket",
	"Connection":        "Upgrade",
	"Sec-WebSocket-Key": "",
	// The request MUST include a header field with the name
	// |Sec-WebSocket-Version|.  The value of this header field MUST be
	// 13.
	"Sec-WebSocket-Version": "13",
}
```

Now that we have the required values set, let's breakdown
`hasRequiredHanshakeHeaders` function.

```go
func hasRequiredHanshakeHeaders(headers map[string]string) bool {
  for k, v := range requiredHeaders {
    value, ok := headers[k]

    if !ok {
      return false
    }

    if v == "" {
      // Header value isn't required for validation
      continue
    }

    if k == "Connection" && strings.Contains(value, v) {
      continue
    }

    if v != value {
      return false
    }
  }

	return true
}
```

After parsing the request I keep the following information for completing the
handshake process. I use the values here to build the handshake response. but
that's the topic for the next post isA.

```go
type HandshakeHeaders struct {
	Host string
	Upgrade string
	Connection string
	SecWebSocketKey string
}
```

I hope you find this post useful, feel free to reach out for any
comments/questions. Happy coding 📜

Full code is
[here](https://github.com/shakram02/nony-chat/blob/f8337df99e0030d09d8ca652ed95102dbd02f6d2/adapters/http/parser/parser.go)
along with
[tests](https://github.com/shakram02/nony-chat/blob/f8337df99e0030d09d8ca652ed95102dbd02f6d2/adapters/http/parser/parser_test.go).
