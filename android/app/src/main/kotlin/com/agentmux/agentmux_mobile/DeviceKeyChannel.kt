package com.agentmux.agentmux_mobile

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec

// The device key a paired computer checks a sent message with
// (SPEC_SEND_FROM_THE_PHONE 5.2.1): ECDSA on P-256 in the Android Keystore,
// signing only, never exportable. In StrongBox when the phone has one, else in
// the TEE or, on an emulator, in software: the OS still never hands the private
// key out. One key per pairing, named by the alias Dart gives it. Needs no
// user authentication: Enter has to just send.
class DeviceKeyChannel : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val alias = call.argument<String>("alias")
            if (alias.isNullOrEmpty()) {
                result.error("bad_args", "no alias", null)
                return
            }
            when (call.method) {
                "create" -> result.success(create(alias))
                "sign" -> {
                    val data = call.argument<ByteArray>("data")
                    if (data == null) {
                        result.error("bad_args", "no data", null)
                        return
                    }
                    result.success(sign(alias, data))
                }
                "delete" -> {
                    keyStore().deleteEntry(alias)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // The class only: a key store error never carries a secret, but
            // there is nothing here worth more than its name.
            result.error("key_store", e.javaClass.simpleName, null)
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun spec(alias: String, strongBox: Boolean): KeyGenParameterSpec {
        val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }
        return builder.build()
    }

    private fun create(alias: String): ByteArray {
        val store = keyStore()
        if (store.containsAlias(alias)) store.deleteEntry(alias)
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
        val pair = try {
            generator.initialize(spec(alias, strongBox = true))
            generator.generateKeyPair()
        } catch (e: Exception) {
            // No StrongBox on this phone (StrongBoxUnavailableException, or
            // an older release's own error): the TEE or software key will do.
            generator.initialize(spec(alias, strongBox = false))
            generator.generateKeyPair()
        }
        return uncompressedPoint(pair.public as ECPublicKey)
    }

    // The 65-byte SEC1 point 0x04 || X || Y, each coordinate 32 bytes.
    private fun uncompressedPoint(key: ECPublicKey): ByteArray {
        val out = ByteArray(65)
        out[0] = 0x04
        copyCoordinate(key.w.affineX, out, 1)
        copyCoordinate(key.w.affineY, out, 33)
        return out
    }

    private fun copyCoordinate(value: BigInteger, out: ByteArray, at: Int) {
        // toByteArray() is signed big-endian: it may have a leading zero byte
        // or be shorter than 32 bytes.
        val bytes = value.toByteArray()
        val length = minOf(bytes.size, 32)
        System.arraycopy(bytes, bytes.size - length, out, at + 32 - length, length)
    }

    private fun sign(alias: String, data: ByteArray): ByteArray {
        val key = keyStore().getKey(alias, null) as? PrivateKey
            ?: throw IllegalStateException("no key")
        val signature = Signature.getInstance("SHA256withECDSA")
        signature.initSign(key)
        signature.update(data)
        return signature.sign()
    }
}
