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
        indent.writeln('${member.name},');
      });
    });
  }

  @override
  void writeDataClass(TypeScriptOptions generatorOptions, Root root, Indent indent, Class classDefinition,
      {required String dartPackageName}) {
    indent.newln();
    addDocumentationComments(indent, classDefinition.documentationComments, _docCommentSpec);
    indent.write('export class ${classDefinition.name} ');
    indent.addScoped('{', '}', () {
      for (final NamedType field in getFieldsInSerializationOrder(classDefinition)) {
        _writeTypedVariable(indent, field);
      }
      indent.newln();
      _writeConstructor(indent, root, classDefinition);
    });
  }

  void _writeTypedVariable(Indent indent, NamedType field, {String prefix = '', String suffix = ';'}) {
    final HostDatatype hostDatatype =
        getFieldHostDatatype(field, (TypeDeclaration type) => _typeScriptTypeForBuiltinDartType(type));

    indent.writeln('$prefix${field.name}${field.type.isNullable ? '?' : ''}: ${hostDatatype.datatype}$suffix');
  }

  void _writeConstructor(Indent indent, Root root, Class classDefinition) {
    indent.write('constructor');
    indent.addScoped('({', '})', () {
      for (final NamedType field in getFieldsInSerializationOrder(classDefinition)) {
        indent.writeln('${field.name},');
      }
      indent.writeln('}: {');
      for (final NamedType field in getFieldsInSerializationOrder(classDefinition)) {
        _writeTypedVariable(indent, field);
      }
    }, addTrailingNewline: false);
    indent.addScoped(' {', '}', () {
      for (final NamedType field in getFieldsInSerializationOrder(classDefinition)) {
        indent.writeln('this.${field.name} = ${field.name};');
      }
    });
  }

  @override
  void writeFileImports(TypeScriptOptions generatorOptions, Root root, Indent indent,
      {required String dartPackageName}) {
    // TODO: Finish, this is just a test
    indent.writeln('// this would be an import.');
  }

  @override
  void writeFilePrologue(TypeScriptOptions generatorOptions, Root root, Indent indent,
      {required String dartPackageName}) {
    // TODO: implement writeFilePrologue
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

String? _typeScriptTypeForBuiltinDartType(TypeDeclaration type) {
  const Map<String, String> typeScriptTypeForDartTypeMap = <String, String>{
    'bool': 'boolean',
    'double': 'number',
    'int': 'number',
    'String': 'string',
    'Uint8List': 'Uint8Array',
    'Int32List': 'Int32Array',
    'Int64List': 'Int64Array',
    'Float64List': 'Float64Array',
  };
  if (typeScriptTypeForDartTypeMap.containsKey(type.baseName)) {
    return typeScriptTypeForDartTypeMap[type.baseName];
  } else if (type.baseName == 'List') {
    return '<${_typeScriptTypeForBuiltinDartType(type.typeArguments[0])}>[]';
  } else if (type.baseName == 'Map') {
    return 'Record<${_typeScriptTypeForBuiltinDartType(type.typeArguments[0])}, ${_typeScriptTypeForBuiltinDartType(type.typeArguments[1])}>';
  } else {
    return null;
  }
}
