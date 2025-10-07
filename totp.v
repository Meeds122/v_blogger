module totp

import crypto.hmac
import crypto.sha1
import encoding.base32
import time

pub struct Authenticator {
pub:
	secret 		string			// Base32 encoded secret
	time_step 	int		= 30	// Time step in seconds - default 30
	digits		int		= 6		// Digits is how long the returned code is. 6-8
}

fn pow10(n int) u32 {
	mut p := u32(1)
	for _ in 0 .. n {
		p *= 10
	}
	return p
}

fn u64_to_be_bytes(x u64) []u8 {
	mut b := []u8{len: 8, init: 0}
	for i in 0 .. 8 {
		b[7 - i] = u8((x >> (u64(i) * 8)) & 0xff)
	}
	return b
}

pub fn (auth Authenticator) generate_totp() !string {
	// Decode the base32 secret
	enc := base32.new_std_encoding()
	key := enc.decode_string(auth.secret)!

	// Calculate the counter from current Unix time
	now := time.now().unix()
	counter := u64(now / i64(auth.time_step))

	// Convert counter to 8-byte big-endian
	buf := u64_to_be_bytes(counter)

	// Compute HMAC-SHA1
	hash := hmac.new(key, buf, sha1.sum, sha1.block_size)

	// Truncate the hash
	offset := int(hash[20 - 1] & 0x0f)
	truncated := (u32(hash[offset] & 0x7f) << 24) |
				 (u32(hash[offset + 1]) << 16) |
				 (u32(hash[offset + 2]) << 8) |
				  u32(hash[offset + 3])

	// Generate the code modulo 10^digits
	p10 := pow10(auth.digits)
	code := int(truncated % p10)

	// Format with leading zeros manually
	mut s := code.str()
	for s.len < auth.digits {
		s = '0' + s
	}
	return s
}

// 	Example usage:
// 	secret := 'JBSWY3DPEHPK3PXP' // Example base32 secret
// 	totp := generate_totp(secret, 30, 6) or { panic(err) }