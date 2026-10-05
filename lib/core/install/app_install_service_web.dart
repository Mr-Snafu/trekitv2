import 'dart:js_interop';

@JS('trekitCanInstall')
external JSBoolean _trekitCanInstall();

@JS('trekitIsStandalone')
external JSBoolean _trekitIsStandalone();

@JS('trekitPromptInstall')
external JSPromise<JSBoolean> _trekitPromptInstall();

const bool isWeb = true;

bool get isStandalone => _trekitIsStandalone().toDart;

bool get canInstall => _trekitCanInstall().toDart;

Future<bool> promptInstall() async =>
    (await _trekitPromptInstall().toDart).toDart;
