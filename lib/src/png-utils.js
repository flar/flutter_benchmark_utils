// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

function makePNG(element, w, h, callback) {
  var canvas = document.createElement('canvas');
  var dpr = window.devicePixelRatio;
  canvas.width = w * dpr;
  canvas.height = h * dpr;
  canvas.style.width = w;
  canvas.style.height = h;
  canvas.style.display = 'none';
  var context = canvas.getContext('2d');
  var img_element = document.createElement('img');
  img_element.onload = function() {
    context.scale(dpr, dpr);
    context.drawImage(img_element, 0, 0);
    var img_data = canvas.toDataURL('image/png');
    var dpr_data = pngApplyDPR(img_data, dpr);
    callback(dpr_data);
  }
  img_element.src = svg2img(element);
}

function saveAsPNG(element, w, h, filename) {
  makePNG(element, w, h, function (png_data) {
    var link = document.createElement('a');
    link.href = png_data;
    link.download = filename;
    link.click();
  });
}

function copyAsPNG(element, w, h) {
  makePNG(element, w, h, function (png_data) {
    fetch(png_data).then(res => res.blob()).then(function(blob) {
      var item = new ClipboardItem({
        [blob.type]: blob
      });
      navigator.clipboard.write([ item ]);
    });
  });
}

function svg2img(element) {
  var svg = element.getElementsByTagName('svg')[0];
  var xml = new XMLSerializer().serializeToString(svg);
  var svg64 = btoa(unescape(encodeURIComponent(xml)));
  var b64start = 'data:image/svg+xml;base64,';
  var image64 = b64start + svg64;
  return image64;
}

function checkSigByte(data, index, val, verbose) {
  if (data[index] == val) return true;
  if (verbose) console.log('byte ' + index + ' of sig is ' + data[index] + ' rather than ' + val);
  return false;
}

function checkSig(data, start, sig, verbose) {
  for (var i = 0; i < sig.length; i++) {
    if (!checkSigByte(data, start + i, sig[i], verbose)) return false;
  }
  return true;
}

function checkChunk(data, start, type) {
  for (var i = 0; i < type.length; i++) {
    if (!checkSigByte(data, start + i, type.charCodeAt(i), false)) return false;
  }
  return true;
}

function getInt(data, index) {
  var number = data[index];
  number = (number << 8) + data[index + 1];
  number = (number << 8) + data[index + 2];
  number = (number << 8) + data[index + 3];
  return number;
}

function setInt(data, index, val) {
  data[index]     = (val >>> 24) & 0xff;
  data[index + 1] = (val >>> 16) & 0xff;
  data[index + 2] = (val >>>  8) & 0xff;
  data[index + 3] = (val       ) & 0xff;
}

function getChunk(data, index) {
  return String.fromCharCode(data[index]) +
         String.fromCharCode(data[index + 1]) +
         String.fromCharCode(data[index + 2]) +
         String.fromCharCode(data[index + 3]);
}

function setChunk(data, index, type) {
  data[index]     = type.charCodeAt(0);
  data[index + 1] = type.charCodeAt(1);
  data[index + 2] = type.charCodeAt(2);
  data[index + 3] = type.charCodeAt(3);
}

function pngApplyDPR(img_data, dpr) {
  var png_fmt = 'data:image/png;base64,';
  if (img_data.indexOf(png_fmt) != 0) {
    console.log('Could not update PNG resolution, image is not of appropriate data type');
    return img_data;
  }
  var png_data = base64StringToBuffer(img_data.substring(png_fmt.length));
  if (!checkSig(png_data, 0, [ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a ], true)) {
    return img_data;
  }
  var chunk_pos = 8;
  while (chunk_pos < png_data.length) {
    var len = getInt(png_data, chunk_pos);
    if (checkChunk(png_data, chunk_pos + 4, 'pHYs', false)) {
      var xPPU = getInt(png_data, chunk_pos + 8);
      var yPPU = getInt(png_data, chunk_pos + 12);
      var type = png_data[chunk_pos + 13];
      if (type != 1) {
        console.log('unrecognized PNG pixel units: ' + type);
        return img_data;
      }
      setInt(png_data, chunk_pos + 8, xPPU * dpr);
      setInt(png_data, chunk_pos + 12, yPPU * dpr);
      setInt(png_data, chunk_pos + 17, png_crc(png_data, chunk_pos + 4, len + 4));
      return png_fmt+base64BufferToString(png_data);
    } else if (checkChunk(png_data, chunk_pos + 4, 'IDAT', false)) {
      var chunk_len = 4 + 4 + 9 + 4;
      var new_array = new Uint8Array(png_data.length + chunk_len);
      new_array.set(png_data.subarray(0, chunk_pos), 0);
      setInt(new_array, chunk_pos, 9);
      setChunk(new_array, chunk_pos + 4, 'pHYs');
      setInt(new_array, chunk_pos + 8, parseInt(72 * dpr / 0.0254, 10));
      setInt(new_array, chunk_pos + 12, parseInt(72 * dpr / 0.0254, 10));
      new_array[chunk_pos + 16] = 1;
      setInt(new_array, chunk_pos + 17, png_crc(new_array, chunk_pos + 4, 9 + 4));
      new_array.set(png_data.subarray(chunk_pos), chunk_pos + chunk_len);
      var new_base_data = base64BufferToString(new_array);
      return png_fmt+new_base_data;
    }
    chunk_pos += len + 12;
  }
  console.log('did not find a pHYs block in the png data.');
  return img_data;
}

