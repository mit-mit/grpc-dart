// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:grpc/src/shared/streams.dart';
import 'package:http2/transport.dart';
import 'package:test/test.dart';

typedef MessageHandler = void Function(StreamMessage message);

List<int> mockEncode(int value) => new List.filled(value, 0);

int mockDecode(List<int> value) => value.length;

Map<String, String> headersToMap(List<Header> headers) =>
    new Map.fromIterable(headers,
        key: (h) => ASCII.decode(h.name), value: (h) => ASCII.decode(h.value));

void validateRequestHeaders(List<Header> headers,
    {String path,
    String authority = 'test',
    String timeout,
    Map<String, String> customHeaders}) {
  final headerMap = headersToMap(headers);
  expect(headerMap[':method'], 'POST');
  expect(headerMap[':scheme'], 'https');
  if (path != null) {
    expect(headerMap[':path'], path);
  }
  expect(headerMap[':authority'], authority);
  expect(headerMap['grpc-timeout'], timeout);
  expect(headerMap['content-type'], 'application/grpc');
  expect(headerMap['te'], 'trailers');
  expect(headerMap['grpc-accept-encoding'], 'identity');
  expect(headerMap['user-agent'], startsWith('dart-grpc/'));

  customHeaders?.forEach((key, value) {
    expect(headerMap[key], value);
  });
}

void validateResponseHeaders(Map<String, String> headers,
    {int status = 200,
    bool allowTrailers = false,
    Map<String, String> customHeaders}) {
  expect(headers[':status'], '200');
  expect(headers['content-type'], startsWith('application/grpc'));
  if (!allowTrailers) {
    expect(headers.containsKey('grpc-status'), isFalse);
    expect(headers.containsKey('grpc-message'), isFalse);
  }
  customHeaders?.forEach((key, value) {
    expect(headers[key], value);
  });
}

void validateResponseTrailers(Map<String, String> trailers,
    {int status = 0, String message, Map<String, String> customTrailers}) {
  expect(trailers['grpc-status'], '$status');
  if (message != null) {
    expect(trailers['grpc-message'], message);
  }
  customTrailers?.forEach((key, value) {
    expect(trailers[key], value);
  });
}

GrpcMetadata validateMetadataMessage(StreamMessage message,
    {bool endStream = false}) {
  expect(message, new isInstanceOf<HeadersStreamMessage>());
  expect(message.endStream, endStream);

  final decoded = new GrpcHttpDecoder().convert(message);
  expect(decoded, new isInstanceOf<GrpcMetadata>());
  return decoded;
}

GrpcData validateDataMessage(StreamMessage message, {bool endStream = false}) {
  expect(message, new isInstanceOf<DataStreamMessage>());
  expect(message.endStream, endStream);

  final decoded = new GrpcHttpDecoder().convert(message);
  expect(decoded, new isInstanceOf<GrpcData>());
  return decoded;
}

void Function(StreamMessage message) headerValidator() {
  return (StreamMessage message) {
    final header = validateMetadataMessage(message, endStream: false);
    validateResponseHeaders(header.metadata, allowTrailers: true);
  };
}

void Function(StreamMessage message) errorTrailerValidator(
    int status, String statusMessage,
    {bool validateHeader = false}) {
  return (StreamMessage message) {
    final trailer = validateMetadataMessage(message, endStream: true);
    if (validateHeader) {
      validateResponseHeaders(trailer.metadata, allowTrailers: true);
    }
    validateResponseTrailers(trailer.metadata,
        status: status, message: statusMessage);
  };
}
