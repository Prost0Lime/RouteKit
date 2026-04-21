package com.example.zapret2manager

import java.io.BufferedReader
import java.io.InputStreamReader

object RootShell {
    fun run(command: String): ShellResult {
        return try {
            val process = ProcessBuilder("su", "-c", command).redirectErrorStream(false).start()
            val stdout = process.inputStream.bufferedReader().use(BufferedReader::readText)
            val stderr = process.errorStream.bufferedReader().use(BufferedReader::readText)
            val code = process.waitFor()
            ShellResult(code, stdout.trim(), stderr.trim())
        } catch (t: Throwable) {
            ShellResult(-1, "", t.message ?: "unknown error")
        }
    }
}
