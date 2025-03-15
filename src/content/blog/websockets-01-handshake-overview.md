---
title: 'Websocket: Handshake overview'
description: 'In this blog post, we will be looking at code that sends server handshake packet.'
pubDate: 'Mar 09 2025'
heroImage: '/websockets-01-handshake-overview.jpg'
---

Let's continue where we left off in the
[previous post](/blog/websockets-00-intro) and describe how the connection is
initiated.

## Client Handhshake

When the client sends the HTTP/1.1 Upgrade request, it doesn't come with empty
hands. The client must provide some values regarding the HTTP request but also
one important value to initiate the websocket connection.

This value is passed in the header with the key: `Sec-WebSocket-Key`

You're probably wondering what does the `Sec-` do, like I did. The RFC didn't
leave this untold story and explained that `Sec-` headers can't be crafted using
Javascript, which is a Sec-urity feature. 👀

This value is a random 4-byte value, which has to be "random" and not coming in
a known sequence (i.e. psuedorandom), another security measure.

Along with the Sec-Websocket-Key, comes a boring Sec-WebSocket-Version, which is
just `13`, always 🙂. At least as far as the RFC is concerned.

## Server Handshake

Why does the server need to reply with a formatted handshake? for security reasons, what I understood from section 1.3 in [RFC6455](https://datatracker.ietf.org/doc/html/rfc6455) is this makes the server sure that the requested connection was from a real client, and the connection request wasn't triggered by a from submission on a webpage, my guess is this helps with denial of service attacks, as websockets allocate system resources that stay "open" (i.e. system's TCP socket) as long as the application is running, I might be wrong but that's my educated guess.

To form the response, the server takes the `Sec-WebSocket-Key` value sent by the client and literally appends: `258EAFA5-E914-47DA-95CA-C5AB0DC85B11` to it then takes the `SHA1` hash of that whole value, then base64 encode it and return it back to the client. 🤷‍

This part was pretty confusing for me what I was reading it to implement it (I'll share implementation of each post soon isA). But the RFC was generous that it had a concrete example.

Let's assume sends this header
```
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
```
Then the server would do the concatenation to get the following:
```
dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11
```

Then SHA1 the previous value to get a binary array, then base64 the resulting array. Then the server would put the resulted base64 encoded string in the `Sec-Websocket-Accept` header, along with the following headers:
```
Upgrade: websocket
Connection: Upgrade
```
Note that the "Upgrade" value in the Connection header is case sensitive 🤐

What about the response line, that's the simple part. The response line MUST be:
```
HTTP/1.1 101 Switching Protocols
```
So, a full response for our sample value would look like this:
```
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=

```
Have you noticed the empty line? 👀 this was one of my pitfalls while doing the implementation, I felt sad to know that I forgot that the HTTP response MUST end with a \r\n in the end. This took me about half an hour to debug 😶.

Now that the server has welcomed the new client, let's move on to some code in the next post isA 🏃
