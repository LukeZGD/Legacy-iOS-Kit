use std::fs::File;
use std::io::{self, Read};

pub fn sha1_file(path: &str) -> io::Result<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha1::new();
    let mut buffer = [0_u8; 1024 * 128];

    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }

    Ok(hasher.finalize_hex())
}

struct Sha1 {
    state: [u32; 5],
    len_bytes: u64,
    buffer: Vec<u8>,
}

impl Sha1 {
    fn new() -> Self {
        Self {
            state: [
                0x6745_2301,
                0xEFCD_AB89,
                0x98BA_DCFE,
                0x1032_5476,
                0xC3D2_E1F0,
            ],
            len_bytes: 0,
            buffer: Vec::with_capacity(64),
        }
    }

    fn update(&mut self, bytes: &[u8]) {
        self.len_bytes += bytes.len() as u64;
        self.buffer.extend_from_slice(bytes);

        while self.buffer.len() >= 64 {
            let mut block = [0_u8; 64];
            block.copy_from_slice(&self.buffer[..64]);
            self.process_block(&block);
            self.buffer.drain(..64);
        }
    }

    fn finalize_hex(mut self) -> String {
        let bit_len = self.len_bytes * 8;
        self.buffer.push(0x80);

        while self.buffer.len() % 64 != 56 {
            self.buffer.push(0);
        }

        self.buffer.extend_from_slice(&bit_len.to_be_bytes());

        let remaining = std::mem::take(&mut self.buffer);
        for block in remaining.chunks(64) {
            let mut fixed = [0_u8; 64];
            fixed.copy_from_slice(block);
            self.process_block(&fixed);
        }

        self.state
            .iter()
            .map(|word| format!("{word:08x}"))
            .collect::<String>()
    }

    fn process_block(&mut self, block: &[u8; 64]) {
        let mut w = [0_u32; 80];

        for (index, chunk) in block.chunks_exact(4).enumerate() {
            w[index] = u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
        }

        for index in 16..80 {
            w[index] = (w[index - 3] ^ w[index - 8] ^ w[index - 14] ^ w[index - 16]).rotate_left(1);
        }

        let [mut a, mut b, mut c, mut d, mut e] = self.state;

        for (index, word) in w.iter().enumerate() {
            let (f, k) = match index {
                0..=19 => ((b & c) | ((!b) & d), 0x5A82_7999),
                20..=39 => (b ^ c ^ d, 0x6ED9_EBA1),
                40..=59 => ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC),
                _ => (b ^ c ^ d, 0xCA62_C1D6),
            };

            let temp = a
                .rotate_left(5)
                .wrapping_add(f)
                .wrapping_add(e)
                .wrapping_add(k)
                .wrapping_add(*word);
            e = d;
            d = c;
            c = b.rotate_left(30);
            b = a;
            a = temp;
        }

        self.state[0] = self.state[0].wrapping_add(a);
        self.state[1] = self.state[1].wrapping_add(b);
        self.state[2] = self.state[2].wrapping_add(c);
        self.state[3] = self.state[3].wrapping_add(d);
        self.state[4] = self.state[4].wrapping_add(e);
    }
}

#[cfg(test)]
mod tests {
    use super::Sha1;

    #[test]
    fn hashes_known_vectors() {
        let mut hasher = Sha1::new();
        hasher.update(b"abc");
        assert_eq!(
            hasher.finalize_hex(),
            "a9993e364706816aba3e25717850c26c9cd0d89d"
        );

        let mut hasher = Sha1::new();
        hasher.update(b"");
        assert_eq!(
            hasher.finalize_hex(),
            "da39a3ee5e6b4b0d3255bfef95601890afd80709"
        );
    }
}
