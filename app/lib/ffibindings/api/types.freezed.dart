// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$EngineError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'EngineError()';
}


}

/// @nodoc
class $EngineErrorCopyWith<$Res>  {
$EngineErrorCopyWith(EngineError _, $Res Function(EngineError) __);
}


/// Adds pattern-matching-related methods to [EngineError].
extension EngineErrorPatterns on EngineError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( EngineError_NotInitialized value)?  notInitialized,TResult Function( EngineError_PackNotFound value)?  packNotFound,TResult Function( EngineError_FormatMismatch value)?  formatMismatch,TResult Function( EngineError_GraphCorrupt value)?  graphCorrupt,TResult Function( EngineError_SearchFailed value)?  searchFailed,TResult Function( EngineError_RoutingFailed value)?  routingFailed,TResult Function( EngineError_InvalidInput value)?  invalidInput,TResult Function( EngineError_Internal value)?  internal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case EngineError_NotInitialized() when notInitialized != null:
return notInitialized(_that);case EngineError_PackNotFound() when packNotFound != null:
return packNotFound(_that);case EngineError_FormatMismatch() when formatMismatch != null:
return formatMismatch(_that);case EngineError_GraphCorrupt() when graphCorrupt != null:
return graphCorrupt(_that);case EngineError_SearchFailed() when searchFailed != null:
return searchFailed(_that);case EngineError_RoutingFailed() when routingFailed != null:
return routingFailed(_that);case EngineError_InvalidInput() when invalidInput != null:
return invalidInput(_that);case EngineError_Internal() when internal != null:
return internal(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( EngineError_NotInitialized value)  notInitialized,required TResult Function( EngineError_PackNotFound value)  packNotFound,required TResult Function( EngineError_FormatMismatch value)  formatMismatch,required TResult Function( EngineError_GraphCorrupt value)  graphCorrupt,required TResult Function( EngineError_SearchFailed value)  searchFailed,required TResult Function( EngineError_RoutingFailed value)  routingFailed,required TResult Function( EngineError_InvalidInput value)  invalidInput,required TResult Function( EngineError_Internal value)  internal,}){
final _that = this;
switch (_that) {
case EngineError_NotInitialized():
return notInitialized(_that);case EngineError_PackNotFound():
return packNotFound(_that);case EngineError_FormatMismatch():
return formatMismatch(_that);case EngineError_GraphCorrupt():
return graphCorrupt(_that);case EngineError_SearchFailed():
return searchFailed(_that);case EngineError_RoutingFailed():
return routingFailed(_that);case EngineError_InvalidInput():
return invalidInput(_that);case EngineError_Internal():
return internal(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( EngineError_NotInitialized value)?  notInitialized,TResult? Function( EngineError_PackNotFound value)?  packNotFound,TResult? Function( EngineError_FormatMismatch value)?  formatMismatch,TResult? Function( EngineError_GraphCorrupt value)?  graphCorrupt,TResult? Function( EngineError_SearchFailed value)?  searchFailed,TResult? Function( EngineError_RoutingFailed value)?  routingFailed,TResult? Function( EngineError_InvalidInput value)?  invalidInput,TResult? Function( EngineError_Internal value)?  internal,}){
final _that = this;
switch (_that) {
case EngineError_NotInitialized() when notInitialized != null:
return notInitialized(_that);case EngineError_PackNotFound() when packNotFound != null:
return packNotFound(_that);case EngineError_FormatMismatch() when formatMismatch != null:
return formatMismatch(_that);case EngineError_GraphCorrupt() when graphCorrupt != null:
return graphCorrupt(_that);case EngineError_SearchFailed() when searchFailed != null:
return searchFailed(_that);case EngineError_RoutingFailed() when routingFailed != null:
return routingFailed(_that);case EngineError_InvalidInput() when invalidInput != null:
return invalidInput(_that);case EngineError_Internal() when internal != null:
return internal(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  notInitialized,TResult Function()?  packNotFound,TResult Function( String field0)?  formatMismatch,TResult Function( String field0)?  graphCorrupt,TResult Function( String field0)?  searchFailed,TResult Function( String field0)?  routingFailed,TResult Function( String field0)?  invalidInput,TResult Function( String field0)?  internal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case EngineError_NotInitialized() when notInitialized != null:
return notInitialized();case EngineError_PackNotFound() when packNotFound != null:
return packNotFound();case EngineError_FormatMismatch() when formatMismatch != null:
return formatMismatch(_that.field0);case EngineError_GraphCorrupt() when graphCorrupt != null:
return graphCorrupt(_that.field0);case EngineError_SearchFailed() when searchFailed != null:
return searchFailed(_that.field0);case EngineError_RoutingFailed() when routingFailed != null:
return routingFailed(_that.field0);case EngineError_InvalidInput() when invalidInput != null:
return invalidInput(_that.field0);case EngineError_Internal() when internal != null:
return internal(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  notInitialized,required TResult Function()  packNotFound,required TResult Function( String field0)  formatMismatch,required TResult Function( String field0)  graphCorrupt,required TResult Function( String field0)  searchFailed,required TResult Function( String field0)  routingFailed,required TResult Function( String field0)  invalidInput,required TResult Function( String field0)  internal,}) {final _that = this;
switch (_that) {
case EngineError_NotInitialized():
return notInitialized();case EngineError_PackNotFound():
return packNotFound();case EngineError_FormatMismatch():
return formatMismatch(_that.field0);case EngineError_GraphCorrupt():
return graphCorrupt(_that.field0);case EngineError_SearchFailed():
return searchFailed(_that.field0);case EngineError_RoutingFailed():
return routingFailed(_that.field0);case EngineError_InvalidInput():
return invalidInput(_that.field0);case EngineError_Internal():
return internal(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  notInitialized,TResult? Function()?  packNotFound,TResult? Function( String field0)?  formatMismatch,TResult? Function( String field0)?  graphCorrupt,TResult? Function( String field0)?  searchFailed,TResult? Function( String field0)?  routingFailed,TResult? Function( String field0)?  invalidInput,TResult? Function( String field0)?  internal,}) {final _that = this;
switch (_that) {
case EngineError_NotInitialized() when notInitialized != null:
return notInitialized();case EngineError_PackNotFound() when packNotFound != null:
return packNotFound();case EngineError_FormatMismatch() when formatMismatch != null:
return formatMismatch(_that.field0);case EngineError_GraphCorrupt() when graphCorrupt != null:
return graphCorrupt(_that.field0);case EngineError_SearchFailed() when searchFailed != null:
return searchFailed(_that.field0);case EngineError_RoutingFailed() when routingFailed != null:
return routingFailed(_that.field0);case EngineError_InvalidInput() when invalidInput != null:
return invalidInput(_that.field0);case EngineError_Internal() when internal != null:
return internal(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class EngineError_NotInitialized extends EngineError {
  const EngineError_NotInitialized(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_NotInitialized);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'EngineError.notInitialized()';
}


}




/// @nodoc


class EngineError_PackNotFound extends EngineError {
  const EngineError_PackNotFound(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_PackNotFound);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'EngineError.packNotFound()';
}


}




/// @nodoc


class EngineError_FormatMismatch extends EngineError {
  const EngineError_FormatMismatch(this.field0): super._();
  

 final  String field0;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineError_FormatMismatchCopyWith<EngineError_FormatMismatch> get copyWith => _$EngineError_FormatMismatchCopyWithImpl<EngineError_FormatMismatch>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_FormatMismatch&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'EngineError.formatMismatch(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EngineError_FormatMismatchCopyWith<$Res> implements $EngineErrorCopyWith<$Res> {
  factory $EngineError_FormatMismatchCopyWith(EngineError_FormatMismatch value, $Res Function(EngineError_FormatMismatch) _then) = _$EngineError_FormatMismatchCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$EngineError_FormatMismatchCopyWithImpl<$Res>
    implements $EngineError_FormatMismatchCopyWith<$Res> {
  _$EngineError_FormatMismatchCopyWithImpl(this._self, this._then);

  final EngineError_FormatMismatch _self;
  final $Res Function(EngineError_FormatMismatch) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EngineError_FormatMismatch(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EngineError_GraphCorrupt extends EngineError {
  const EngineError_GraphCorrupt(this.field0): super._();
  

 final  String field0;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineError_GraphCorruptCopyWith<EngineError_GraphCorrupt> get copyWith => _$EngineError_GraphCorruptCopyWithImpl<EngineError_GraphCorrupt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_GraphCorrupt&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'EngineError.graphCorrupt(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EngineError_GraphCorruptCopyWith<$Res> implements $EngineErrorCopyWith<$Res> {
  factory $EngineError_GraphCorruptCopyWith(EngineError_GraphCorrupt value, $Res Function(EngineError_GraphCorrupt) _then) = _$EngineError_GraphCorruptCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$EngineError_GraphCorruptCopyWithImpl<$Res>
    implements $EngineError_GraphCorruptCopyWith<$Res> {
  _$EngineError_GraphCorruptCopyWithImpl(this._self, this._then);

  final EngineError_GraphCorrupt _self;
  final $Res Function(EngineError_GraphCorrupt) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EngineError_GraphCorrupt(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EngineError_SearchFailed extends EngineError {
  const EngineError_SearchFailed(this.field0): super._();
  

 final  String field0;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineError_SearchFailedCopyWith<EngineError_SearchFailed> get copyWith => _$EngineError_SearchFailedCopyWithImpl<EngineError_SearchFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_SearchFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'EngineError.searchFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EngineError_SearchFailedCopyWith<$Res> implements $EngineErrorCopyWith<$Res> {
  factory $EngineError_SearchFailedCopyWith(EngineError_SearchFailed value, $Res Function(EngineError_SearchFailed) _then) = _$EngineError_SearchFailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$EngineError_SearchFailedCopyWithImpl<$Res>
    implements $EngineError_SearchFailedCopyWith<$Res> {
  _$EngineError_SearchFailedCopyWithImpl(this._self, this._then);

  final EngineError_SearchFailed _self;
  final $Res Function(EngineError_SearchFailed) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EngineError_SearchFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EngineError_RoutingFailed extends EngineError {
  const EngineError_RoutingFailed(this.field0): super._();
  

 final  String field0;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineError_RoutingFailedCopyWith<EngineError_RoutingFailed> get copyWith => _$EngineError_RoutingFailedCopyWithImpl<EngineError_RoutingFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_RoutingFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'EngineError.routingFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EngineError_RoutingFailedCopyWith<$Res> implements $EngineErrorCopyWith<$Res> {
  factory $EngineError_RoutingFailedCopyWith(EngineError_RoutingFailed value, $Res Function(EngineError_RoutingFailed) _then) = _$EngineError_RoutingFailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$EngineError_RoutingFailedCopyWithImpl<$Res>
    implements $EngineError_RoutingFailedCopyWith<$Res> {
  _$EngineError_RoutingFailedCopyWithImpl(this._self, this._then);

  final EngineError_RoutingFailed _self;
  final $Res Function(EngineError_RoutingFailed) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EngineError_RoutingFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EngineError_InvalidInput extends EngineError {
  const EngineError_InvalidInput(this.field0): super._();
  

 final  String field0;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineError_InvalidInputCopyWith<EngineError_InvalidInput> get copyWith => _$EngineError_InvalidInputCopyWithImpl<EngineError_InvalidInput>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_InvalidInput&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'EngineError.invalidInput(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EngineError_InvalidInputCopyWith<$Res> implements $EngineErrorCopyWith<$Res> {
  factory $EngineError_InvalidInputCopyWith(EngineError_InvalidInput value, $Res Function(EngineError_InvalidInput) _then) = _$EngineError_InvalidInputCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$EngineError_InvalidInputCopyWithImpl<$Res>
    implements $EngineError_InvalidInputCopyWith<$Res> {
  _$EngineError_InvalidInputCopyWithImpl(this._self, this._then);

  final EngineError_InvalidInput _self;
  final $Res Function(EngineError_InvalidInput) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EngineError_InvalidInput(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EngineError_Internal extends EngineError {
  const EngineError_Internal(this.field0): super._();
  

 final  String field0;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineError_InternalCopyWith<EngineError_Internal> get copyWith => _$EngineError_InternalCopyWithImpl<EngineError_Internal>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_Internal&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'EngineError.internal(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EngineError_InternalCopyWith<$Res> implements $EngineErrorCopyWith<$Res> {
  factory $EngineError_InternalCopyWith(EngineError_Internal value, $Res Function(EngineError_Internal) _then) = _$EngineError_InternalCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$EngineError_InternalCopyWithImpl<$Res>
    implements $EngineError_InternalCopyWith<$Res> {
  _$EngineError_InternalCopyWithImpl(this._self, this._then);

  final EngineError_Internal _self;
  final $Res Function(EngineError_Internal) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EngineError_Internal(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$NavigationEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NavigationEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'NavigationEvent()';
}


}

/// @nodoc
class $NavigationEventCopyWith<$Res>  {
$NavigationEventCopyWith(NavigationEvent _, $Res Function(NavigationEvent) __);
}


/// Adds pattern-matching-related methods to [NavigationEvent].
extension NavigationEventPatterns on NavigationEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NavigationEvent_Rerouted value)?  rerouted,TResult Function( NavigationEvent_Instruction value)?  instruction,TResult Function( NavigationEvent_Arrived value)?  arrived,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NavigationEvent_Rerouted() when rerouted != null:
return rerouted(_that);case NavigationEvent_Instruction() when instruction != null:
return instruction(_that);case NavigationEvent_Arrived() when arrived != null:
return arrived(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NavigationEvent_Rerouted value)  rerouted,required TResult Function( NavigationEvent_Instruction value)  instruction,required TResult Function( NavigationEvent_Arrived value)  arrived,}){
final _that = this;
switch (_that) {
case NavigationEvent_Rerouted():
return rerouted(_that);case NavigationEvent_Instruction():
return instruction(_that);case NavigationEvent_Arrived():
return arrived(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NavigationEvent_Rerouted value)?  rerouted,TResult? Function( NavigationEvent_Instruction value)?  instruction,TResult? Function( NavigationEvent_Arrived value)?  arrived,}){
final _that = this;
switch (_that) {
case NavigationEvent_Rerouted() when rerouted != null:
return rerouted(_that);case NavigationEvent_Instruction() when instruction != null:
return instruction(_that);case NavigationEvent_Arrived() when arrived != null:
return arrived(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Route field0)?  rerouted,TResult Function( RouteStep field0)?  instruction,TResult Function()?  arrived,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NavigationEvent_Rerouted() when rerouted != null:
return rerouted(_that.field0);case NavigationEvent_Instruction() when instruction != null:
return instruction(_that.field0);case NavigationEvent_Arrived() when arrived != null:
return arrived();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Route field0)  rerouted,required TResult Function( RouteStep field0)  instruction,required TResult Function()  arrived,}) {final _that = this;
switch (_that) {
case NavigationEvent_Rerouted():
return rerouted(_that.field0);case NavigationEvent_Instruction():
return instruction(_that.field0);case NavigationEvent_Arrived():
return arrived();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Route field0)?  rerouted,TResult? Function( RouteStep field0)?  instruction,TResult? Function()?  arrived,}) {final _that = this;
switch (_that) {
case NavigationEvent_Rerouted() when rerouted != null:
return rerouted(_that.field0);case NavigationEvent_Instruction() when instruction != null:
return instruction(_that.field0);case NavigationEvent_Arrived() when arrived != null:
return arrived();case _:
  return null;

}
}

}

/// @nodoc


class NavigationEvent_Rerouted extends NavigationEvent {
  const NavigationEvent_Rerouted(this.field0): super._();
  

 final  Route field0;

/// Create a copy of NavigationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NavigationEvent_ReroutedCopyWith<NavigationEvent_Rerouted> get copyWith => _$NavigationEvent_ReroutedCopyWithImpl<NavigationEvent_Rerouted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NavigationEvent_Rerouted&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'NavigationEvent.rerouted(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NavigationEvent_ReroutedCopyWith<$Res> implements $NavigationEventCopyWith<$Res> {
  factory $NavigationEvent_ReroutedCopyWith(NavigationEvent_Rerouted value, $Res Function(NavigationEvent_Rerouted) _then) = _$NavigationEvent_ReroutedCopyWithImpl;
@useResult
$Res call({
 Route field0
});




}
/// @nodoc
class _$NavigationEvent_ReroutedCopyWithImpl<$Res>
    implements $NavigationEvent_ReroutedCopyWith<$Res> {
  _$NavigationEvent_ReroutedCopyWithImpl(this._self, this._then);

  final NavigationEvent_Rerouted _self;
  final $Res Function(NavigationEvent_Rerouted) _then;

/// Create a copy of NavigationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NavigationEvent_Rerouted(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as Route,
  ));
}


}

/// @nodoc


class NavigationEvent_Instruction extends NavigationEvent {
  const NavigationEvent_Instruction(this.field0): super._();
  

 final  RouteStep field0;

/// Create a copy of NavigationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NavigationEvent_InstructionCopyWith<NavigationEvent_Instruction> get copyWith => _$NavigationEvent_InstructionCopyWithImpl<NavigationEvent_Instruction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NavigationEvent_Instruction&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'NavigationEvent.instruction(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NavigationEvent_InstructionCopyWith<$Res> implements $NavigationEventCopyWith<$Res> {
  factory $NavigationEvent_InstructionCopyWith(NavigationEvent_Instruction value, $Res Function(NavigationEvent_Instruction) _then) = _$NavigationEvent_InstructionCopyWithImpl;
@useResult
$Res call({
 RouteStep field0
});




}
/// @nodoc
class _$NavigationEvent_InstructionCopyWithImpl<$Res>
    implements $NavigationEvent_InstructionCopyWith<$Res> {
  _$NavigationEvent_InstructionCopyWithImpl(this._self, this._then);

  final NavigationEvent_Instruction _self;
  final $Res Function(NavigationEvent_Instruction) _then;

/// Create a copy of NavigationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NavigationEvent_Instruction(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as RouteStep,
  ));
}


}

/// @nodoc


class NavigationEvent_Arrived extends NavigationEvent {
  const NavigationEvent_Arrived(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NavigationEvent_Arrived);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'NavigationEvent.arrived()';
}


}




// dart format on
