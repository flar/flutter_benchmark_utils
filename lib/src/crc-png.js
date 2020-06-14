// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/* Adapted from reference ANSI C version: https://www.w3.org/TR/PNG-CRCAppendix.html */

/* Table of CRCs of all 8-bit messages. */
var crc_table = [];

/* Make the table for a fast CRC. */
function make_png_crc_table() {
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (k = 0; k < 8; k++) {
      if ((c & 1) == 1) {
        c = 0xedb88320 ^ (c >>> 1);
      } else {
        c = c >>> 1;
      }
    }
    crc_table.push(c);
  }
}

/* Update a running CRC with the bytes buf[0..len-1]--the CRC
 * should be initialized to all 1's, and the transmitted value
 * is the 1's complement of the final running CRC (see the
 * crc() routine below)).
 */

function update_png_crc(crc, buf, index, len) {
  if (crc_table.length == 0) {
    make_png_crc_table();
  }

  for (var n = 0; n < len; n++) {
    crc = crc_table[(crc ^ buf[index + n]) & 0xff] ^ (crc >>> 8);
  }

  return crc;
}

/* Return the CRC of the bytes buf[0..len-1]. */
function png_crc(buf, index, len) {
  return update_png_crc(0xffffffff, buf, index, len) ^ 0xffffffff;
}
