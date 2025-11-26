// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

/// Create anchor element with download attribute
HTMLAnchorElement createAnchorElement(String href, String? suggestedName) =>
    (document.createElement('a') as HTMLAnchorElement)
      ..href = href
      ..download = suggestedName ?? 'download';

/// Add an element to a container and click it
void addElementToContainerAndClick(Element container, HTMLElement element) {
  // Add the element and click it
  // All previous elements will be removed before adding the new one
  container.appendChild(element);
  element.click();
}

/// Initializes a DOM container where elements can be injected.
Element ensureInitialized(String id) {
  Element? target = document.querySelector('#$id');
  if (target == null) {
    final Element targetElement = document.createElement('flt-x-file')..id = id;

    document.body!.appendChild(targetElement);
    target = targetElement;
  }
  return target;
}

/// Determines if the browser is Safari from its vendor string.
/// (This is the same check used in flutter/engine)
bool isSafari() {
  return window.navigator.vendor == 'Apple Computer, Inc.';
}

/// Converts an html [Blob] object to a [Uint8List], through a [FileReader].
Future<Uint8List> blobToByteBuffer(Blob blob) async {
  final FileReader reader = FileReader();
  reader.readAsArrayBuffer(blob);

  await reader.onLoadEnd.first;

  final Uint8List? result = reader.result as Uint8List?;

  if (result == null) {
    throw Exception('Cannot read bytes from Blob. Is it still available?');
  }

  return result;
}

/// Creates a [Blob] from a bunch of [bytes] and an optional [mimeType].
Blob bytesToBlob(Uint8List bytes, String? mimeType) {
  return (mimeType == null)
      ? Blob(<JSUint8Array>[bytes.toJS].toJS)
      : Blob(<JSUint8Array>[bytes.toJS].toJS, BlobPropertyBag(type: mimeType));
}
