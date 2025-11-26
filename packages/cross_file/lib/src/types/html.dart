// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:web/web.dart' as web;

import '../web_helpers/blob_stream.dart';
import '../web_helpers/web_helpers.dart';
import 'base.dart';

// Four Gigabytes, in bytes.
const int _fourGigabytes = 4 * 1024 * 1024 * 1024;

/// A CrossFile that works on web.
///
/// It wraps the bytes of a selected file.
class XFile extends XFileBase {
  /// Construct a CrossFile object from its ObjectUrl.
  ///
  /// Optionally, this can be initialized with `bytes` and `length`
  /// so no http requests are performed to retrieve files later.
  ///
  /// `name` needs to be passed from the outside, since it's only available
  /// while handling [web.File]s (when the ObjectUrl is created).
  // ignore: use_super_parameters
  XFile(
    String path, {
    String? mimeType,
    String? name,
    int? length,
    Uint8List? bytes,
    DateTime? lastModified,
    @visibleForTesting CrossFileTestOverrides? overrides,
  }) : _mimeType = mimeType,
       _path = path,
       _length = length,
       _overrides = overrides,
       _lastModified = lastModified ?? DateTime.fromMillisecondsSinceEpoch(0),
       _name = name ?? '',
       super(path) {
    // Cache `bytes` as Blob, if passed.
    if (bytes != null) {
      _browserBlob = bytesToBlob(bytes, mimeType);
    }
  }

  /// Construct an CrossFile from its data
  XFile.fromData(
    Uint8List bytes, {
    String? mimeType,
    String? name,
    int? length,
    DateTime? lastModified,
    String? path,
    @visibleForTesting CrossFileTestOverrides? overrides,
  }) : _mimeType = mimeType,
       _length = length,
       _overrides = overrides,
       _lastModified = lastModified ?? DateTime.fromMillisecondsSinceEpoch(0),
       _name = name ?? '',
       super(path) {
    _browserBlob = bytesToBlob(bytes, mimeType);
    _path = web.URL.createObjectURL(_browserBlob!);
  }

  /// Construct a CrossFile from a JS [File] (extends Blob).
  XFile.fromHtmlFile(
    web.File file, {
    String? path,
    @visibleForTesting CrossFileTestOverrides? overrides,
  }) : _browserBlob = file,
       _name = file.name,
       _mimeType = file.type,
       _length = file.size,
       _lastModified = DateTime.fromMillisecondsSinceEpoch(file.lastModified),
       _overrides = overrides,
       _path = web.URL.createObjectURL(file),
       super(path);

  /// Construct a CrossFile from a JS [File] (extends Blob).
  XFile.fromHtmlBlob(
    web.Blob blob, {
    String? name,
    DateTime? lastModified,
    String? path,
    @visibleForTesting CrossFileTestOverrides? overrides,
  }) : _browserBlob = blob,
       _name = name ?? 'unnamed',
       _mimeType = blob.type,
       _length = blob.size,
       _lastModified = lastModified ?? DateTime.now(),
       _overrides = overrides,
       _path = web.URL.createObjectURL(blob),
       super(path);

  // Overridable (meta) data that can be specified by the constructors.

  // MimeType of the file (eg: "image/gif").
  final String? _mimeType;

  // Name (with extension) of the file (eg: "anim.gif")
  final String _name;

  // Path of the file (must be a valid Blob URL, when set manually!)
  late String _path;

  // The size of the file (in bytes).
  final int? _length;

  // The time the file was last modified.
  final DateTime _lastModified;

  // The link to the binary object in the browser memory (Blob).
  // This can be passed in (as `bytes` in the constructor) or derived from
  // [_path] with a fetch request.
  // (Similar to a (read-only) dart:io File.)
  web.Blob? _browserBlob;

  // An html Element that will be used to trigger a "save as" dialog later.
  // TODO(dit): https://github.com/flutter/flutter/issues/91400 Remove this _target.
  late web.Element _target;

  // Overrides for testing
  // TODO(dit): https://github.com/flutter/flutter/issues/91400 Remove these _overrides,
  // they're only used to Save As...
  final CrossFileTestOverrides? _overrides;

  bool get _hasTestOverrides => _overrides != null;

  @override
  String? get mimeType => _mimeType;

  @override
  String get name => _name;

  @override
  String get path => _path;

  @override
  Future<DateTime> lastModified() async => _lastModified;

  Future<web.Blob> get _blob async {
    if (_browserBlob != null) {
      return _browserBlob!;
    }

    // Attempt to re-hydrate the blob from the `path` via a (local) HttpRequest.
    // Note that safari hangs if the Blob is >=4GB, so bail out in that case.
    if (isSafari() && _length != null && _length >= _fourGigabytes) {
      throw Exception('Safari cannot handle XFiles larger than 4GB.');
    }

    final blobCompleter = Completer<web.Blob>();

    late web.XMLHttpRequest request;
    request = web.XMLHttpRequest()
      ..open('get', path, true)
      ..responseType = 'blob'
      ..onLoad.listen((web.ProgressEvent e) {
        assert(request.response != null, 'The Blob backing this XFile cannot be null!');
        blobCompleter.complete(request.response! as web.Blob);
      })
      ..onError.listen((web.ProgressEvent e) {
        if (e.type == 'error') {
          blobCompleter.completeError(
            Exception('Could not load Blob from its URL. Has it been revoked?'),
          );
        }
      })
      ..send();

    return blobCompleter.future;
  }

  @override
  Future<Uint8List> readAsBytes() async {
    return _blob.then(blobToByteBuffer);
  }

  @override
  Future<int> length() async => _length ?? (await _blob).size;

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    return readAsBytes().then(encoding.decode);
  }

  // TODO(dit): https://github.com/flutter/flutter/issues/91867 Implement openRead properly.
  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    return BlobStream(_blob, start, end);
  }

  /// Saves the data of this CrossFile at the location indicated by path.
  /// For the web implementation, the path variable is ignored.
  // TODO(dit): https://github.com/flutter/flutter/issues/91400
  // Move implementation to web_helpers.dart
  @override
  Future<void> saveTo(String path) async {
    // Create a DOM container where the anchor can be injected.
    _target = ensureInitialized('__x_file_dom_element');

    // Create an <a> tag with the appropriate download attributes and click it
    // May be overridden with CrossFileTestOverrides
    final web.HTMLAnchorElement element = _hasTestOverrides
        ? _overrides!.createAnchorElement(this.path, name) as web.HTMLAnchorElement
        : createAnchorElement(this.path, name);

    // Clear the children in _target and add an element to click
    while (_target.children.length > 0) {
      _target.removeChild(_target.children.item(0)!);
    }
    addElementToContainerAndClick(_target, element);
  }
}

/// Overrides some functions to allow testing
// TODO(dit): https://github.com/flutter/flutter/issues/91400
// Move this to web_helpers_test.dart
@visibleForTesting
class CrossFileTestOverrides {
  /// Default constructor for overrides
  CrossFileTestOverrides({required this.createAnchorElement});

  /// For overriding the creation of the file input element.
  web.Element Function(String href, String suggestedName) createAnchorElement;
}
