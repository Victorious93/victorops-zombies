package com.victorious.zombie.net

import com.victorious.zombie.logic.Characters
import com.victorious.zombie.sim.PlayerInput
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.*

private fun waitFor(ms: Long = 5000, cond: () -> Boolean): Boolean {
    val end = System.currentTimeMillis() + ms
    while (System.currentTimeMillis() < end) { if (cond()) return true; Thread.sleep(10) }
    return cond()
}

class TcpHardeningTest {
    private fun listenerCounting(closed: AtomicInteger) = object : NetLink.Listener {
        override fun onMessage(type: String, data: String) {}
        override fun onClosed() { closed.incrementAndGet() }
    }

    @Test fun overLongLineClosesLinkInsteadOfBufferingIt() {
        val ss = ServerSocket(0); val c = Socket("127.0.0.1", ss.localPort); val s = ss.accept()
        val closed = AtomicInteger(); val errors = CopyOnWriteArrayList<Throwable>()
        val old = Thread.getDefaultUncaughtExceptionHandler(); Thread.setDefaultUncaughtExceptionHandler { _, e -> errors += e }
        try {
            val link = TcpLink(s); link.listener = listenerCounting(closed)
            val chunk = ByteArray(64 * 1024) { 'a'.code.toByte() }; val out = c.getOutputStream()
            var sentKb = 0
            try { while (sentKb < 64 * 1024 && closed.get() == 0) { out.write(chunk); sentKb += 64 } } catch (_: Exception) { /* receiver hung up */ }
            assertTrue(waitFor { closed.get() == 1 }, "link was not closed")
            assertTrue(sentKb < 8 * 1024, "receiver accepted ${sentKb}KB of one unterminated line")
            assertTrue(errors.isEmpty(), "receive thread died: $errors")
            assertTrue(waitFor { s.isClosed })
        } finally { Thread.setDefaultUncaughtExceptionHandler(old); runCatching { c.close() }; ss.close() }
    }

    @Test fun normalAndCrLfMessagesStillParse() {
        val ss = ServerSocket(0); val c = Socket("127.0.0.1", ss.localPort); val s = ss.accept()
        val got = CopyOnWriteArrayList<Pair<String, String>>()
        val link = TcpLink(s); link.listener = object : NetLink.Listener { override fun onMessage(type: String, data: String) { got += type to data }; override fun onClosed() {} }
        c.getOutputStream().apply { write("zj martha\r\nzi 10,0,1,0\nzb bye\n".toByteArray()); flush() }
        assertTrue(waitFor { got.size == 3 })
        assertEquals(listOf("zj" to "martha", "zi" to "10,0,1,0", "zb" to "bye"), got.toList())
        link.close(); c.close(); ss.close()
    }

    @Test fun remoteCloseReleasesLocalSocketAndNotifiesOnce() {
        val ss = ServerSocket(0); val c = Socket("127.0.0.1", ss.localPort); val s = ss.accept()
        val closed = AtomicInteger(); val disposed = AtomicInteger()
        val link = TcpLink(s, onDispose = { disposed.incrementAndGet() }); link.listener = listenerCounting(closed)
        c.close()
        assertTrue(waitFor { s.isClosed }, "socket left open after peer disconnected")
        Thread.sleep(100)
        assertEquals(1, closed.get()); assertEquals(1, disposed.get())
        link.close(); Thread.sleep(50)
        assertEquals(1, closed.get(), "close() after remote close must not notify again"); ss.close()
    }

    @Test fun lastMessageIsFlushedBeforeCloseCompletes() {
        val ss = ServerSocket(0); val c = Socket("127.0.0.1", ss.localPort); val s = ss.accept()
        val link = TcpLink(s)
        link.send("zf", "full"); link.close()
        val line = c.getInputStream().bufferedReader().readLine()
        assertEquals("zf full", line); c.close(); ss.close()
    }

    @Test fun fifthPlayerIsToldHostIsFullOverRealSockets() {
        val session = HostSession.create(Characters.SNOOP)
        val host = TcpHost(0) { session.attach(it) }
        val clients = (1..5).map { ClientSession(TcpLink.connect("127.0.0.1", host.port), "martha") }
        val end = System.currentTimeMillis() + 5000
        while (System.currentTimeMillis() < end && !clients[4].rejected) { session.tick(0.016f); clients.forEach { it.tick(0.016f, PlayerInput()) }; Thread.sleep(16) }
        try {
            assertEquals(3, clients.take(4).count { it.playerId >= 0 }) // host is player 0
            assertTrue(clients[4].rejected, "5th joiner never got the 'full' reply")
            assertEquals(-1, clients[4].playerId)
        } finally { host.close(); clients.forEach { it.close() } }
    }

    @Test fun acceptLoopSurvivesAFailingPeerSetup() {
        val seen = AtomicInteger()
        val host = TcpHost(0) { if (seen.incrementAndGet() == 1) error("boom") }
        try {
            Socket("127.0.0.1", host.port).close()
            assertTrue(waitFor { seen.get() >= 1 })
            val second = Socket("127.0.0.1", host.port)
            assertTrue(waitFor { seen.get() >= 2 }, "host stopped accepting after one failure"); second.close()
        } finally { host.close() }
    }

    @Test fun silentConnectionsAreDroppedAndCapped() {
        val peers = CopyOnWriteArrayList<NetLink>()
        val host = TcpHost(0, maxPeers = 3, handshakeMs = 300) { peers += it }
        try {
            val socks = (1..6).map { Socket("127.0.0.1", host.port) }
            assertTrue(waitFor { peers.size == 3 }); Thread.sleep(100)
            assertEquals(3, peers.size, "connections beyond maxPeers must be dropped")
            // every silent socket (accepted or refused) is closed by the host: reads see EOF
            socks.forEach { s -> s.soTimeout = 3000; assertEquals(-1, s.getInputStream().read(), "silent socket was left open") }
            // slots are free again afterwards
            val again = Socket("127.0.0.1", host.port)
            assertTrue(waitFor { peers.size == 4 }, "slots were not released"); again.close(); socks.forEach { it.close() }
        } finally { host.close() }
    }

    @Test fun talkativeConnectionIsNotDroppedByHandshakeTimeout() {
        val got = AtomicInteger(); val closed = AtomicInteger()
        val host = TcpHost(0, handshakeMs = 800) { it.listener = object : NetLink.Listener { override fun onMessage(type: String, data: String) { got.incrementAndGet() }; override fun onClosed() { closed.incrementAndGet() } } }
        try {
            val s = Socket("127.0.0.1", host.port); Thread.sleep(150) // let the host attach its listener
            s.getOutputStream().apply { write("zj snoop\n".toByteArray()); flush() }
            assertTrue(waitFor { got.get() == 1 })
            Thread.sleep(1500) // well past the handshake deadline
            s.getOutputStream().apply { write("zi 0,0,0,0\n".toByteArray()); flush() }
            assertTrue(waitFor { got.get() == 2 }, "established connection was dropped"); assertEquals(0, closed.get()); s.close()
        } finally { host.close() }
    }
}
