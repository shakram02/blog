---
title: 'Websocket: Introduction'
description: 'Introduction to websockets series.'
pubDate: 'March 08 2025'
heroImage: '/websockets-00-intro.jpg'
---

## Movitation

Yesterday I hit a wall when using websockets library in `x/net` for golang. I
decided to make my own (very simple) server implantation for WebSockets protocol
starting from TCP 🥁.

The wall was that for some reason that I don't know, whenever I try to pass the
socket to a goroutine it was just closing the connection without a clue, after
many trials I gave up on the library. 🤐

So, I went to the WebSockets [RFC6455](https://datatracker.ietf.org/doc/html/rfc6455) and started the
implementation from source, reading an RFC isn't very straight forward but that
was going to be another practice for me. I previously implemented TFTP and UDP
from the RFC directly before. Not an easy task, but a fun one. 🤽‍

Through the next posts, I'll be sharing my pitfalls during reading and
implementing the RFC starting the from the next post, I'll just give a light
overview about the protocol.

### What is this WebSockets?

WebSockets is a protocol that allows two-way communication (bidirectional),
between clients and servers. This means both clients and servers can send and
receive messages.

### Why is Websocket protocol important?

WebSockets is a major enabler for chat applications.

Since WebSockets is a bidirectional communication protocol, it adds a missing
functionality to basic HTTP in an efficient way. HTTP is a request-response
protocol, clients can't easily receive "events/updates" from the server without
requesting it. This is wasteful when it comes to resources on the server.

### How do they work?

Well, websockets tries not to be an intruder protocol that breaks things, so it
starts its connection as an innocent HTTP/1.1 with a special type of GET request
called Upgrade. This is the very first request that's sent to the server to
initiate a Websocket connection. After that, the system socket is left open with 
the server for communication going both ways.

What happens rest will come later isA 👀
