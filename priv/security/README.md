# Password lists

This directory holds the two lists of the password policy in
`Espalier.Accounts.PasswordPolicy` (`docs/plan/tasks/0004-accounts-sessions.md`, step 14).

- `Espalier.Application` reads both files at boot and stores them in `:persistent_term`.
- Every line of each file is one entry. The files contain no comments and no empty lines.
- `PasswordPolicy.prepare/1` normalizes every password to Unicode NFC with
  `String.normalize(password, :nfc)` (`docs/plan/README.md`, section 6.4, and section 15,
  decision D12).
- The check compares `String.downcase/1` of the NFC-normalized password with the lists.
  Both lists therefore hold lowercase entries in NFC.

## common-passwords.txt

The file holds common passwords with 15 or more Unicode code points, one per line,
sorted in byte order.

| Item | Value |
|---|---|
| Source project | SecLists, <https://github.com/danielmiessler/SecLists> |
| Source file | `Passwords/Common-Credentials/xato-net-10-million-passwords-1000000.txt` at commit `dd50d1561e3cbad84f016a592f7f9371bef7ada9` |
| Source URL | <https://raw.githubusercontent.com/danielmiessler/SecLists/dd50d1561e3cbad84f016a592f7f9371bef7ada9/Passwords/Common-Credentials/xato-net-10-million-passwords-1000000.txt> |
| Source SHA-256 | `424a3e03a17df0a2bc2b3ca749d81b04e79d59cb7aeec8876a5a3f308d0caf51` |
| Source size | 1,000,000 lines, ordered from most to least common |
| License | MIT License, <https://github.com/danielmiessler/SecLists/blob/dd50d1561e3cbad84f016a592f7f9371bef7ada9/LICENSE> (full text below) |
| Retrieval date | 2026-10-08 |
| Entries | 10898 |

### Filter

The filter applies these rules to each line of the source file:

1. Drop lines that are not valid UTF-8.
2. Normalize to NFC with `String.normalize(&1, :nfc)`, then lowercase with `String.downcase/1`.
3. Keep entries with 15 to 128 code points, counted with `length(String.codepoints(&1))`.
4. Drop entries that contain a control character (Unicode category Cc) or any whitespace
   character other than a plain space (U+0020).
5. Remove duplicates and sort with `Enum.sort/1` (byte order).

The source holds fewer than 20,000 qualifying entries, so the filter keeps all of them.
Gitleaks (`gitleaks detect --no-git --no-banner --redact --source priv/security`) flags
no entry, so no further step removes entries.

### Commands

Download the source into a scratch directory outside the repository:

```sh
SRC_DIR=$(mktemp -d)
curl -fsSL -o "$SRC_DIR/source.txt" \
  https://raw.githubusercontent.com/danielmiessler/SecLists/dd50d1561e3cbad84f016a592f7f9371bef7ada9/Passwords/Common-Credentials/xato-net-10-million-passwords-1000000.txt
sha256sum "$SRC_DIR/source.txt"
```

Run the filter from the repository root:

```sh
nix-shell --run "elixir -e '[src, out] = System.argv(); bad = ~r/\p{Cc}|[^\S ]/u; File.read!(src) |> String.split(<<10>>) |> Enum.filter(&String.valid?/1) |> Enum.map(&String.downcase(String.normalize(&1, :nfc))) |> Enum.filter(&(length(String.codepoints(&1)) in 15..128)) |> Enum.reject(&Regex.match?(bad, &1)) |> Enum.uniq() |> Enum.sort() |> Enum.map(&[&1, 10]) |> then(&File.write!(out, &1))' $SRC_DIR/source.txt priv/security/common-passwords.txt"
```

To update the list, change the commit in the URL, run both commands, and update the
checksum, the retrieval date and the number of entries in this file.

### License of the source list

```text
MIT License

Copyright (c) 2018 Daniel Miessler

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## context-words.txt

The file holds the product name and words of the learning and sign-in domain, one
lowercase NFC word per line, sorted in byte order. It has 20 entries.

- Operators add their organization's own words through the environment variable
  `PASSWORD_CONTEXT_WORDS`, as a comma-separated list, for example
  `PASSWORD_CONTEXT_WORDS=exampleorg,examplecity`.
- The words of the file and of `PASSWORD_CONTEXT_WORDS` pass through
  `String.normalize(&1, :nfc)` before they are lowercased.
- The check takes the lowercase letters of the password alone, with digits, whitespace and
  punctuation removed. It rejects the password when these letters equal a context word.
  For example, `Credentials 2026!!` reduces to `credentials` and is rejected.
- The same check also rejects a password that contains the lowercase local part of the
  user's e-mail address or the display name, each when 4 or more code points long. These
  values come from the account and not from this file.
