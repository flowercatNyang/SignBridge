package com.example.testsign

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Never persist the backend access token as plaintext or include it in logs. */
class AssistantConnectionStore(context: Context) {
    private val prefs = context.getSharedPreferences("signbridge_assistant", Context.MODE_PRIVATE)
    private val alias = "signbridge.assistant.connection.v1"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(alias, null) as? SecretKey
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        return generator.generateKey()
    }

    fun load(): Map<String, String> {
        if (!prefs.contains("baseUrl")) return emptyMap()
        val stored = prefs.getString("tokenEncrypted", "") ?: ""
        val token = if (stored.isEmpty()) "" else {
            try {
                val parts = stored.split(":")
                require(parts.size == 2)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, key(),
                    GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
                String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8)
            } catch (error: Exception) {
                // A restored backup cannot decrypt a token without its original device key.
                throw IllegalStateException("저장된 연결 토큰을 읽지 못했습니다. 서버 연결 설정에서 다시 저장해 주세요.")
            }
        }
        return mapOf("baseUrl" to (prefs.getString("baseUrl", "") ?: ""), "accessToken" to token)
    }

    fun save(url: String, token: String) {
        require(url.length <= 2000 && token.length <= 4096) { "연결 설정이 너무 깁니다." }
        val encrypted = if (token.isEmpty()) "" else {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
                Base64.encodeToString(cipher.doFinal(token.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        }
        check(prefs.edit().putString("baseUrl", url).putString("tokenEncrypted", encrypted).commit()) {
            "서버 연결 설정을 저장하지 못했습니다."
        }
    }
}
