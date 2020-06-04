base64_char_table = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
base64_reverse_table = null;

function base64MakeReverseTable() {
  if (base64_reverse_table) return;
  base64_reverse_table = new Array(256);
  var val = 0;
  for (var i = 0; i < base64_char_table.length; i++) {
    var ch = base64_char_table.charCodeAt(i);
    base64_reverse_table[ch] = val++;
  }
}

function base64StringToBuffer(base64_string) {
  base64MakeReverseTable();

  var str_len = base64_string.length;
  while (str_len > 0 && base64_string[str_len - 1] == '=') str_len--;

  var uIntArray = new Uint8Array(str_len * 6 / 8);
  var uIndex = 0;
  for (var i = 0; i < str_len; i += 4) {
    var b64_0 = base64_reverse_table[base64_string.charCodeAt(i)];
    var b64_1 = base64_reverse_table[base64_string.charCodeAt(i + 1)];
    var b64_2 = base64_reverse_table[base64_string.charCodeAt(i + 2)];
    var b64_3 = base64_reverse_table[base64_string.charCodeAt(i + 3)];

    var enc_0 = ((b64_0 << 2) | (b64_1 >> 4)) & 0xff;
    var enc_1 = ((b64_1 << 4) | (b64_2 >> 2)) & 0xff;
    var enc_2 = ((b64_2 << 6) | (b64_3     )) & 0xff;

    uIntArray[uIndex++] = enc_0;
    if (uIndex < uIntArray.length) uIntArray[uIndex++] = enc_1;
    if (uIndex < uIntArray.length) uIntArray[uIndex++] = enc_2;
  }
  return uIntArray;
}

function base64BufferToString(uIntArray) {
  var arrLen = uIntArray.length;
  var strLen = parseInt((arrLen + 2) / 3) * 4;
  var str = '';

  var bits = 0;
  var numBits = 0;
  var arrIndex = 0;
  while (arrIndex < arrLen || numBits > 0) {
    if (numBits < 6) {
      while (numBits <= 24 && arrIndex < arrLen) {
        bits |= (uIntArray[arrIndex++] << (24 - numBits));
        numBits += 8;
      }
    }
    str += base64_char_table[bits >>> 26];
    bits <<= 6;
    numBits -= 6;
  }
  while ((str.length & 3) != 0) {
    str += '=';
  }
  return str;
}
