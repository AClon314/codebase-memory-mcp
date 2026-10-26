#!/usr/bin/env bun
/**
 * Expose cbm's loopback-only HTTP API/UI on another address.
 *
 * cbm deliberately binds 127.0.0.1 and rejects foreign Host/Origin headers.
 * This proxy keeps that invariant on the wire to cbm, but lets a browser or
 * another local process reach it:
 *
 *   client -> 0.0.0.0:9749 -> 127.0.0.1:9751
 *
 * It rewrites Host to cbm's own authority and drops Origin, so cbm's
 * same-server checks still pass. No authentication is added.
 *
 * This is a generic cbm HTTP/WebSocket proxy, not specific to cbm's embedded
 * React UI.
 */
import http from "node:http";
import net from "node:net";

const UPSTREAM_HOST = process.env.CBM_UPSTREAM_HOST ?? "127.0.0.1";
const UPSTREAM_PORT = Number(process.env.CBM_UPSTREAM_PORT ?? 9751);
const LISTEN_HOST = process.env.PROXY_HOST ?? "0.0.0.0";
const LISTEN_PORT = Number(process.env.PROXY_PORT ?? 9749);
const UPSTREAM_AUTHORITY = `${UPSTREAM_HOST}:${UPSTREAM_PORT}`;

function upstreamHeaders(headers: http.IncomingHttpHeaders): http.OutgoingHttpHeaders {
  const out: http.OutgoingHttpHeaders = { ...headers, host: UPSTREAM_AUTHORITY };
  // cbm's origin check only accepts its own loopback origin. Dropping the
  // browser Origin keeps the check on the safe path; Host still names cbm.
  delete out.origin;
  return out;
}

const server = http.createServer((req, res) => {
  const proxy = http.request(
    {
      host: UPSTREAM_HOST,
      port: UPSTREAM_PORT,
      method: req.method,
      path: req.url,
      headers: upstreamHeaders(req.headers),
    },
    (upstream) => {
      res.writeHead(upstream.statusCode ?? 502, upstream.headers);
      upstream.pipe(res);
    }
  );
  proxy.on("error", (error) => {
    if (!res.headersSent) res.writeHead(502, { "content-type": "text/plain" });
    res.end(`cbm upstream error: ${error.message}`);
  });
  req.pipe(proxy);
});

server.on("upgrade", (req, socket, head) => {
  const upstream = net.connect(UPSTREAM_PORT, UPSTREAM_HOST, () => {
    const headers = upstreamHeaders(req.headers);
    const lines = [`${req.method} ${req.url} HTTP/1.1`];
    for (const [name, value] of Object.entries(headers)) {
      if (Array.isArray(value)) for (const item of value) lines.push(`${name}: ${item}`);
      else if (value !== undefined) lines.push(`${name}: ${value}`);
    }
    upstream.write(lines.join("\r\n") + "\r\n\r\n");
    if (head.length > 0) upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });
  upstream.on("error", () => socket.destroy());
  socket.on("error", () => upstream.destroy());
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  console.log(`cbm HTTP proxy: http://${LISTEN_HOST}:${LISTEN_PORT}/ -> ${UPSTREAM_AUTHORITY}`);
});
