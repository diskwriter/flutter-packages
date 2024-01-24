import 'package:collection/collection.dart';

import 'ast.dart';
import 'functional.dart';
import 'generator.dart';
import 'generator_tools.dart';

/// Documentation comment open symbol;
const String _docCommentPrefix = '/**';
const String _docCommentContinuation = ' * ';
const String _docCommentSuffix = ' */';

/// Documentation comment spec.
const DocumentCommentSpecification _docCommentSpec = DocumentCommentSpecification(
  _docCommentPrefix,
  blockContinuationToken: _docCommentContinuation,
  closeCommentToken: _docCommentSuffix,
);

/// TypeScript generator options.
class TypeScriptOptions {
  /// Default constructor.
  const TypeScriptOptions();

  /// /// Creates a [TypeScriptOptions] from a Map representation where:
  /// `x = TypeScriptOptions.fromMap(x.toMap())`.
  static TypeScriptOptions fromMap(Map<String, Object> map) {
    return const TypeScriptOptions();
  }

  /// Converts a [TypeScriptOptions] to a Map representation where:
  /// `x = TypeScriptOptions.fromMap(x.toMap())`.
  Map<String, Object> toMap() {
    final Map<String, Object> result = <String, Object>{};
    return result;
  }
}

/// Class that manages all typescript code generation
class TypeScriptGenerator extends StructuredGenerator<TypeScriptOptions> {
  @override
  void writeEnum(TypeScriptOptions generatorOptions, Root root, Indent indent, Enum anEnum,
      {required String dartPackageName}) {
    indent.newln();
    indent.write('export enum ${anEnum.name} ');
    indent.addScoped('{', '}', () {
      enumerate(anEnum.members, (int index, final EnumMember member) {
        if (anEnum.hasMetaData('StringEnum')) {
          indent.writeln("${member.name} = '${anEnum.name}.${member.name}',");
        } else {
          indent.writeln('${member.name},');
        }
      });
    });
  }

  @override
  void writeDataClass(TypeScriptOptions generatorOptions, Root root, Indent indent, Class classDefinition,
      {required String dartPackageName}) {
    // Here we want to determine if we want to render this data class as an actual ES class object
    // or as a TypeScript interface.
    // We can differentiate between the two by checking if the `@TypeScriptInterface` annotation is present
    // on the meta data of the class.
    if (classDefinition.hasMetaData('TypeScriptInterface')) {
      _writeInterface(generatorOptions, root, indent, classDefinition, dartPackageName: dartPackageName);
    } else {
      _writeClass(generatorOptions, root, indent, classDefinition, dartPackageName: dartPackageName);
    }
  }

  void _writeClass(TypeScriptOptions generatorOptions, Root root, Indent indent, Class classDefinition,
      {required String dartPackageName}) {
    indent.newln();
    addDocumentationComments(indent, classDefinition.documentationComments, _docCommentSpec);
    indent.write(
        'export class ${classDefinition.name}${classDefinition.hasSuperClass ? ' extends ${classDefinition.superClass}' : ''} ');
    indent.addScoped('{', '}', () {
      for (final NamedType field in getFieldsInSerializationOrder(classDefinition)) {
        _writeTypedVariable(indent, field);
      }
      indent.newln();
      _writeConstructor(indent, root, classDefinition);
      _writeClassDecode(indent, root, classDefinition);
      _writeClassEncode(indent, classDefinition);
    });
  }

  void _writeInterface(TypeScriptOptions generatorOptions, Root root, Indent indent, Class classDefinition,
      {required String dartPackageName}) {
    indent.newln();
    indent.write('export interface ${classDefinition.name} ');
    indent.addScoped('{', '}', () {
      for (final NamedType field in getFieldsInSerializationOrder(classDefinition)) {
        _writeTypedVariable(indent, field);
      }
    });

    // TODO Write encode?
    _writeDecodeMethod(indent, classDefinition);
  }

  void _writeTypedVariable(
    Indent indent,
    NamedType field, {
    String prefix = '',
    String suffix = ';',
    bool snakeCase = false,
  }) {
    final HostDatatype hostDatatype =
        getFieldHostDatatype(field, (TypeDeclaration type) => _typeScriptTypeForBuiltinDartType(type));

    indent.writeln(
        '$prefix${snakeCase ? _camelCaseToSnakeCase(field.name) : field.name}${field.type.isNullable ? '?' : ''}: ${hostDatatype.datatype}$suffix');
  }

  String _asTypeCast(NamedType field, {String prefix = '', String suffix = ','}) {
    final HostDatatype hostDatatype =
        getFieldHostDatatype(field, (TypeDeclaration type) => _typeScriptTypeForBuiltinDartType(type));

    return '$prefix as ${hostDatatype.datatype}$suffix';
  }

  void _writeDecodeMethod(Indent indent, Class classDefinition) {
    indent.newln();
    indent.write(
      'export function decode${classDefinition.name}(request: Record<string, any>): ${classDefinition.name} ',
    );
    indent.writeScoped('{', '}', () {
      indent.writeScoped('return {', '};', () {
        for (final NamedType field in getFieldsInSerializationOrder(classDefinition)) {
          if (field.type.isNullable) {
            indent.writeln('${field.name}: request.${_camelCaseToSnakeCase(field.name)} != null');
            indent.writeln(
                '${indent.tab}? ${_asTypeCast(field, prefix: 'request.${_camelCaseToSnakeCase(field.name)}', suffix: '')}');
            indent.writeln('${indent.tab}: undefined,');
            continue;
          }

          indent
              .writeln('${field.name}: ${_asTypeCast(field, prefix: 'request.${_camelCaseToSnakeCase(field.name)}')}');
        }
      });
    });
  }

  void _writeClassDecode(Indent indent, Root root, Class classDefinition) {
    indent.newln();
    indent.writeScoped('static deSerialize(data: Record<string, any | undefined>) : ${classDefinition.name} {', '}',
        () {
      indent.writeScoped('return new ${classDefinition.name}({', '});', () {
        for (final NamedType field in getFieldsInSerializationOrder(classDefinition)) {
          /// Casting enums is good enough for typescript apparently...
          /// (In fact you don't even HAVE to cast but I cannot deal with that.)
          if (field.type.isClass) {
            if (field.type.isNullable) {
              indent.writeln("${field.name}: data['${_camelCaseToSnakeCase(field.name)}'] !== undefined");
              indent.writeln(
                  "${indent.tab}? ${field.type.baseName}.deSerialize(data['${_camelCaseToSnakeCase(field.name)}'] as Record<string, any>)");
              indent.writeln('${indent.tab}: undefined,');
              continue;
            } else {
              indent.writeln(
                  "${field.name}: ${field.type.baseName}.deSerialize(data['${_camelCaseToSnakeCase(field.name)}'] as Record<string, any>),");
            }
          } else {
            if (field.type.isNullable) {
              indent.writeln("${field.name}: data['${_camelCaseToSnakeCase(field.name)}'] !== undefined");
              indent.writeln(
                  "${indent.tab}? ${_asTypeCast(field, prefix: "data['${_camelCaseToSnakeCase(field.name)}']", suffix: '')}");
              indent.writeln('${indent.tab}: undefined,');
              continue;
            }

            indent.writeln(
                '${field.name}: ${_asTypeCast(field, prefix: "data['${_camelCaseToSnakeCase(field.name)}']")}');
          }
        }
      });
    });
  }

  void _writeClassEncode(Indent indent, Class classDefiniton) {
    indent.newln();
    indent.write('serialize(): ');
    indent.addScoped('{', '}', () {
      for (final NamedType field in getFieldsInSerializationOrder(classDefiniton)) {
        _writeTypedVariable(indent, field, snakeCase: true);
      }
      if (classDefiniton.hasMetaData('SerializeWithRuntimeType')) {
        indent.writeln('type: string,');
      }
    }, addTrailingNewline: false);

    /// Not having the constructor parameter type as an interface makes that regular
    /// `writeScoped` method gets confused with the indentation so we lower it  manually here
    indent.dec();
    indent.writeScoped(' {', '}', () {
      indent.inc();
      indent.writeScoped('return {', '};', () {
        for (final NamedType field in getFieldsInSerializationOrder(classDefiniton)) {
          indent.writeln('${_camelCaseToSnakeCase(field.name)}: this.${field.name},');
        }
        if (classDefiniton.hasMetaData('SerializeWithRuntimeType')) {
          indent.writeln("type: '${classDefiniton.getSerializeWithRuntimeTypeMeta()}',");
        }
      });
    });
  }

  String _camelCaseToSnakeCase(String value) {
    final RegExp regExp = RegExp(r'(?=[A-Z])');
    final List<String> split = value.split(regExp).map((String s) => s.toLowerCase()).toList();
    return split.join('_');
  }

  void _writeConstructor(Indent indent, Root root, Class classDefinition) {
    indent.write('${classDefinition.hasMetaData('NoDefaultConstructor') ? 'private ' : ''}constructor');
    indent.addScoped('({', '})', () {
      for (final NamedType field in getFieldsInSerializationOrder(classDefinition)) {
        indent.writeln('${field.name},');
      }

      /// Not having these function parameters as an interface confuses the regular `writeScoped` method
      /// so we do manual indentation here.
      indent.dec();
      indent.writeln('}: {');
      indent.inc();
      for (final NamedType field in getFieldsInSerializationOrder(classDefinition)) {
        _writeTypedVariable(indent, field);
      }
    }, addTrailingNewline: false);
    indent.addScoped(' {', '}', () {
      if (classDefinition.hasSuperClass) {
        indent.writeln('super({});');
      }
      for (final NamedType field in getFieldsInSerializationOrder(classDefinition)) {
        indent.writeln('this.${field.name} = ${field.name};');
      }
    });

    if (classDefinition.hasNamedConstructors) {
      for (final String namedConstructor in classDefinition.namedConstructors) {
        final bool hasConstructorNonDefaultValues = classDefinition.fields.firstWhereOrNull((NamedType field) =>
                field.constructorDefaultValues == null ||
                !field.constructorDefaultValues!.keys.contains(namedConstructor)) !=
            null;

        indent.newln();
        if (!hasConstructorNonDefaultValues) {
          indent.writeln('static $namedConstructor(): ${classDefinition.name} {');
        } else {
          indent.writeln('static $namedConstructor({');
          indent.nest(1, () {
            final List<NamedType> allFields = getFieldsInSerializationOrder(classDefinition).toList();
            for (final NamedType field in allFields) {
              if (field.constructorDefaultValues == null ||
                  !field.constructorDefaultValues!.keys.contains(namedConstructor)) {
                indent.writeln('${field.name},');
              }
            }
          });
          indent.writeln('} : {');
          indent.nest(1, () {
            final List<NamedType> allFields = getFieldsInSerializationOrder(classDefinition).toList();
            for (final NamedType field in allFields) {
              if (field.constructorDefaultValues == null ||
                  !field.constructorDefaultValues!.keys.contains(namedConstructor)) {
                indent.writeln(
                    '${field.name}${field.type.isNullable ? '?' : ''}: ${_typeScriptTypeForBuiltinDartType(field.type)};');
              }
            }
          });
          indent.writeln('}): ${classDefinition.name} {');
        }
        indent.nest(1, () {
          indent.writeScoped('return new ${classDefinition.name}({', '})', () {
            final List<NamedType> allFields = getFieldsInSerializationOrder(classDefinition).toList();
            for (final NamedType field in allFields) {
              if (field.constructorDefaultValues == null ||
                  !field.constructorDefaultValues!.keys.contains(namedConstructor)) {
                indent.writeln('${field.name},');
              } else {
                indent.writeln(
                    '${field.name}: ${_mapNullToUndefined(field.constructorDefaultValues![namedConstructor])},');
              }
            }
          });
        });
        indent.writeln('}');
      }
    }
  }

  @override
  void writeFileImports(TypeScriptOptions generatorOptions, Root root, Indent indent,
      {required String dartPackageName}) {
    // TODO: Finish, this is just a test
  }

  @override
  void writeFilePrologue(TypeScriptOptions generatorOptions, Root root, Indent indent,
      {required String dartPackageName}) {
    indent.writeln('// ${getGeneratedCodeWarning()}');
    indent.writeln('// $seeAlsoWarning');
  }

  @override
  void writeFlutterApi(TypeScriptOptions generatorOptions, Root root, Indent indent, Api api,
      {required String dartPackageName}) {
    // TODO: implement writeFlutterApi
  }

  @override
  void writeHostApi(TypeScriptOptions generatorOptions, Root root, Indent indent, Api api,
      {required String dartPackageName}) {
    // TODO: implement writeHostApi
  }
}

String _mapNullToUndefined(String? value) {
  return value == 'null' || value == null ? 'undefined' : value;
}

String? _typeScriptTypeForBuiltinDartType(TypeDeclaration type) {
  const Map<String, String> typeScriptTypeForDartTypeMap = <String, String>{
    'bool': 'boolean',
    'double': 'number',
    'int': 'number',
    'String': 'string',
    'dynamic': 'any',
    'Uint8List': 'Uint8Array',
    'Int32List': 'Int32Array',
    'Int64List': 'BigInt64Array',
    'Float64List': 'Float64Array',
  };
  if (typeScriptTypeForDartTypeMap.containsKey(type.baseName)) {
    return typeScriptTypeForDartTypeMap[type.baseName];
  } else if (type.baseName == 'List') {
    return '<${_typeScriptTypeForBuiltinDartType(type.typeArguments[0])}>[]';
  } else if (type.baseName == 'Map') {
    if (type.typeArguments.length != 2) {
      throw Exception('Map type must have exactly two type arguments.');
    }
    return 'Record<${_typeScriptTypeForBuiltinDartType(type.typeArguments[0])}, ${_typeScriptTypeForBuiltinDartType(type.typeArguments[1])}>';
  } else {
    return null;
  }
}
