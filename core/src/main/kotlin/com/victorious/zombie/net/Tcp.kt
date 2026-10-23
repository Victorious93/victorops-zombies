package com.victorious.zombie.net

import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/** Shared daemon timer for connection housekeeping (handshake deadlines, stuck-close fallbacks). */
private val reaper = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "zombie-net-reaper").apply { isDaemon = true } }

/**
 * Wi-Fi/LAN link: one line per message, "type data\n". Works with no internet connection.
 *
 * - Lines longer than [MAX_LINE] are never buffered: the link is closed as soon as the limit is crossed.
 * - If [handshakeMs] > 0 and the peer has not sent a complete message by then, the link is closed.
 * - [close] lets already-queued messages flush first (so a final "full"/"bye" reaches the peer), then closes the socket.
 * - [onDispose] runs once when the link is finished, whichever side ended it.
 */
class TcpLink(private val socket: Socket, handshakeMs: Long = 0, private val onDispose: (() -> Unit)? = null) : NetLink {
    @Volatile override var listener: NetLink.Listener? = null
    private val closed = AtomicBoolean(false)
    @Volatile private var heardFrom = false
    private val out: OutputStream = socket.getOutputStream()
    private val sender = Executors.newSingleThreadExecutor { r -> Thread(r, "zombie-net-send").apply { isDaemon = true } }

    init {
        thread(isDaemon = true, name = "zombie-net-recv") {
            try {
                val input = BufferedInputStream(socket.getInputStream())
                while (!closed.get()) {
                    val line = readLine(input) ?: break
                    val sp = line.indexOf(' ')
                    if (sp > 0) { heardFrom = true; listener?.onMessage(line.substring(0, sp), line.substring(sp + 1)) }
                }
            } catch (_: Exception) { /* closed or reset */ }
            finish()
        }
        if (handshakeMs > 0) reaper.schedule({ if (!heardFrom) finish() }, handshakeMs, TimeUnit.MILLISECONDS)
    }

    /** Reads one '\n'-terminated line, holding at most [MAX_LINE] bytes. Null on EOF or an over-long line. */
    private fun readLine(input: InputStream): String? {
        val buf = ByteArrayOutputStream(256)
        while (true) {
            val b = input.read()
            if (b < 0) return null
            if (b == '\n'.code) return buf.toString(Charsets.UTF_8.name()).trimEnd('\r')
            if (buf.size() >= MAX_LINE) return null
            buf.write(b)
        }
    }

    override fun send(type: String, data: String) {
        if (closed.get()) return
        val bytes = "$type ${data.replace('\n', ' ')}\n".toByteArray(Charsets.UTF_8)
        try { sender.execute { try { out.write(bytes); out.flush() } catch (_: Exception) { finish() } } } catch (_: Exception) { /* shut down */ }
    }

    /** Stops accepting messages and closes after queued ones are written. A stalled peer cannot hold the socket open forever. */
    override fun close() { finish() }

    private fun finish() {
        if (!closed.compareAndSet(false, true)) return
        runCatching { sender.execute { runCatching { socket.close() } } }
        sender.shutdown()
        reaper.schedule({ runCatching { socket.close() } }, CLOSE_GRACE_MS, TimeUnit.MILLISECONDS)
        listener?.onClosed()
        onDispose?.invoke()
    }

    companion object {
        const val MAX_LINE = 64 * 1024
        const val CLOSE_GRACE_MS = 2000L
        fun connect(host: String, port: Int, timeoutMs: Int = 8000): TcpLink {
            val s = Socket(); s.tcpNoDelay = true; s.connect(InetSocketAddress(host, port), timeoutMs); return TcpLink(s)
        }
    }
}

/**
 * Accepts players on [port] (0 = pick a free one). At most [maxPeers] connections are alive at once; extras are dropped
 * on arrival, and a connection that sends nothing within [handshakeMs] is dropped, so idle sockets cannot pile up.
 * A failure on one connection never stops the accept loop.
 */
class TcpHost(port: Int = DEFAULT_PORT, private val maxPeers: Int = DEFAULT_MAX_PEERS, private val handshakeMs: Long = DEFAULT_HANDSHAKE_MS, private val onPeer: (NetLink) -> Unit) {
    private val server = ServerSocket(port)
    val port: Int get() = server.localPort
    @Volatile private var closed = false
    private val live = AtomicInteger()

    init {
        thread(isDaemon = true, name = "zombie-net-accept") {
            while (!closed) {
                val s = try { server.accept() } catch (_: Exception) {
                    if (closed || server.isClosed) break
                    Thread.sleep(ACCEPT_RETRY_MS); continue // transient (e.g. out of file descriptors): keep serving
                }
                if (live.get() >= maxPeers) { runCatching { s.close() }; continue }
                live.incrementAndGet()
                val link = try { s.tcpNoDelay = true; TcpLink(s, handshakeMs) { live.decrementAndGet() } }
                catch (_: Exception) { live.decrementAndGet(); runCatching { s.close() }; continue }
                try { onPeer(link) } catch (_: Exception) { link.close() }
            }
        }
    }

    fun close() { closed = true; runCatching { server.close() } }

    companion object {
        const val DEFAULT_PORT = 47464
        const val DEFAULT_MAX_PEERS = 8
        const val DEFAULT_HANDSHAKE_MS = 5000L
        private const val ACCEPT_RETRY_MS = 100L
        /** A LAN address friends can type in, or null. */
        fun localAddress(): String? = runCatching {
            NetworkInterface.getNetworkInterfaces().toList().filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList() }.filterIsInstance<Inet4Address>().firstOrNull { it.isSiteLocalAddress }?.hostAddress
        }.getOrNull()
    }
}
