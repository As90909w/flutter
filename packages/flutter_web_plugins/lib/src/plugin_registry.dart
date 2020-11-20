// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// TODO(hterkelsen): Why is this _MessageHandler duplicated here?
typedef _MessageHandler = Future<ByteData?>? Function(ByteData?);

/// This class registers web platform plugins.
///
/// An instance of this class is available as [webPluginRegistry].
class PluginRegistry {
  /// Creates a plugin registry.
  ///
  /// The argument selects the [BinaryMessenger] to use. An
  /// appropriate value would be [pluginBinaryMessenger].
  PluginRegistry(this._binaryMessenger);

  final BinaryMessenger _binaryMessenger;

  /// Creates a registrar for the given plugin implementation class.
  Registrar registrarFor(Type key) => Registrar(_binaryMessenger);

  /// Registers this plugin handler with the engine, so that unrecognized
  /// platform messages are forwarded to the registry, where they can be
  /// correctly dispatched to one of the registered plugins.
  ///
  /// Code generated by the `flutter` tool automatically calls this method
  /// for the global [webPluginRegistry] at startup.
  ///
  /// Only one [PluginRegistry] can be registered at a time. Calling this
  /// method a second time silently unregisters the first [PluginRegistry]
  /// and replaces it with the new one.
  ///
  /// This method uses a function called `webOnlySetPluginHandler` in
  /// the [dart:ui] library. That function is only available when
  /// compiling for the web.
  void registerMessageHandler() {
    // The function below is only defined in the Web dart:ui.
    // ignore: undefined_function
    ui.webOnlySetPluginHandler(_binaryMessenger.handlePlatformMessage);
  }
}

/// A registrar for a particular plugin.
///
/// Gives access to a [BinaryMessenger] which has been configured to receive
/// platform messages from the framework side.
class Registrar {
  /// Creates a registrar with the given [BinaryMessenger].
  Registrar(this.messenger);

  /// A [BinaryMessenger] configured to receive platform messages from the
  /// framework side.
  ///
  /// Use this [BinaryMessenger] when creating platform channels in order for
  /// them to receive messages from the platform side. For example:
  ///
  /// ```dart
  /// class MyPlugin {
  ///   static void registerWith(Registrar registrar) {
  ///     final MethodChannel channel = MethodChannel(
  ///       'com.my_plugin/my_plugin',
  ///       const StandardMethodCodec(),
  ///       registrar.messenger,
  ///     );
  ///     final MyPlugin instance = MyPlugin();
  ///     channel.setMethodCallHandler(instance.handleMethodCall);
  ///   }
  ///   // ...
  /// }
  /// ```
  final BinaryMessenger messenger;
}

/// The default plugin registry for the web.
///
/// Uses [pluginBinaryMessenger] as the [BinaryMessenger].
final PluginRegistry webPluginRegistry = PluginRegistry(pluginBinaryMessenger);

/// A [BinaryMessenger] which does the inverse of the default framework
/// messenger.
///
/// Instead of sending messages from the framework to the engine, this
/// receives messages from the framework and dispatches them to registered
/// plugins.
class _PlatformBinaryMessenger extends BinaryMessenger {
  final Map<String, _MessageHandler> _handlers = <String, _MessageHandler>{};

  /// Receives a platform message from the framework.
  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) async {
    ByteData? response;
    try {
      final MessageHandler? handler = _handlers[channel];
      if (handler != null) {
        response = await handler(data);
      }
    } catch (exception, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: 'flutter web plugins',
        context: ErrorDescription('during a framework-to-plugin message'),
      ));
    } finally {
      if (callback != null) {
        callback(response);
      }
    }
  }

  /// Sends a platform message from the platform side back to the framework.
  @override
  Future<ByteData?> send(String channel, ByteData? message) {
    final Completer<ByteData?> completer = Completer<ByteData?>();
    ui.window.onPlatformMessage!(channel, message, (ByteData? reply) {
      try {
        completer.complete(reply);
      } catch (exception, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'flutter web plugins',
          context: ErrorDescription('during a plugin-to-framework message'),
        ));
      }
    });
    return completer.future;
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    if (handler == null)
      _handlers.remove(channel);
    else
      _handlers[channel] = handler;
  }

  @override
  bool checkMessageHandler(String channel, MessageHandler? handler) => _handlers[channel] == handler;

  @override
  void setMockMessageHandler(
    String channel,
    MessageHandler? handler,
  ) {
    throw FlutterError(
      'Setting mock handlers is not supported on the platform side.',
    );
  }

  @override
  bool checkMockMessageHandler(String channel, MessageHandler? handler) {
    throw FlutterError(
      'Setting mock handlers is not supported on the platform side.',
    );
  }
}

/// The default [BinaryMessenger] for Flutter web plugins.
///
/// This is the value used for [webPluginRegistry]'s [PluginRegistry]
/// constructor argument.
final BinaryMessenger pluginBinaryMessenger = _PlatformBinaryMessenger();
