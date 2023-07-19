const std = @import("std");
const Endian = @import("./shared.zig").Endian;
const U1 = u8;
const U2 = u16;
const U4 = u32;

const Reader = struct {
    bytecode: []const U1,
    pos: U4 = 0,
    allocator: std.mem.Allocator = std.heap.page_allocator,
    constantPool: []ConstantInfo = undefined,

    const This = @This();

    fn peek1(this: *const This) U1 {
        const byte = this.bytecode[this.pos];
        return byte;
    }

    fn peek2(this: *const This) U2 {
        return Endian.Big.load(U2, this.bytecode[this.pos .. this.pos + 2]);
    }

    fn peek4(this: *const This) U4 {
        return Endian.Big.load(U4, this.bytecode[this.pos .. this.pos + 4]);
    }

    fn read1(this: *This) U1 {
        const v = this.peek1();
        this.pos += 1;
        return v;
    }

    fn read2(this: *This) U2 {
        const v = this.peek2();
        this.pos += 2;
        return v;
    }

    fn read4(this: *This) U4 {
        const v = this.peek4();
        this.pos += 4;
        return v;
    }

    /// read a slice provided with an item readFn
    fn reads(this: *This, comptime T: type, size: usize, readFn: *const fn (reader: *Reader) T) []T {
        const slice = this.make(T, size);
        for (0..size) |i| {
            slice[i] = readFn(this);
        }
        return slice;
    }

    fn read1s(this: *This, length: U4) []U1 {
        return this.reads(U1, length, Reader.read1);
    }

    fn lookup(this: *const This, comptime T: type, index: usize) T {
        const constantInfo = this.constantPool[index];

        return switch (constantInfo) {
            inline else => |c| if (@TypeOf(c) == T) c else unreachable,
        };
    }

    fn make(this: *This, comptime T: type, size: usize) []T {
        return this.allocator.alloc(T, size) catch unreachable;
    }
};

pub const ClassFile = struct {
    magic: [4]U1,
    minorVersion: U2,
    majorVersion: U2,
    constantPoolCount: U2,
    constantPool: []ConstantInfo,
    accessFlags: U2,
    thisClass: U2,
    superClass: U2,
    interfaceCount: U2,
    interfaces: []U2,
    fieldsCount: U2,
    fields: []FieldInfo,
    methodsCount: U2,
    methods: []MethodInfo,
    attributeCount: U2,
    attributes: []AttributeInfo,

    const This = @This();
    pub fn read(bytecode: []const U1) This {
        var reader: Reader = .{ .bytecode = bytecode };
        const magic = reader.read1s(4)[0..4].*;
        const minorVersion = reader.read2();
        const majorVersion = reader.read2();
        const constantPoolCount = reader.read2();
        const constantPool = reader.make(ConstantInfo, constantPoolCount);
        var i: usize = 1;
        while (i < constantPoolCount) {
            const constantInfo = ConstantInfo.read(&reader);
            constantPool[i] = constantInfo;
            std.debug.print("{d} ", .{i});
            switch (constantInfo) {
                inline else => |c| std.debug.print("{} \n", .{c}),
            }
            switch (constantInfo) {
                .long, .double => i += 2,
                else => i += 1,
            }
        }
        reader.constantPool = constantPool;
        const accessFlags = reader.read2();
        const thisClass = reader.read2();
        const superClass = reader.read2();
        const interfaceCount = reader.read2();
        const interfaces = reader.reads(U2, interfaceCount, Reader.read2);
        const fieldsCount = reader.read2();
        const fields = reader.reads(FieldInfo, fieldsCount, FieldInfo.read);
        const methodsCount = reader.read2();
        const methods = reader.reads(MethodInfo, methodsCount, MethodInfo.read);
        const attributeCount = reader.read2();
        const attributes = reader.reads(AttributeInfo, attributeCount, AttributeInfo.read);
        return .{
            .magic = magic,
            .minorVersion = minorVersion,
            .majorVersion = majorVersion,
            .constantPoolCount = constantPoolCount,
            .constantPool = constantPool,
            .accessFlags = accessFlags,
            .thisClass = thisClass,
            .superClass = superClass,
            .interfaceCount = interfaceCount,
            .interfaces = interfaces,
            .fieldsCount = fieldsCount,
            .fields = fields,
            .methodsCount = methodsCount,
            .methods = methods,
            .attributeCount = attributeCount,
            .attributes = attributes,
        };
    }

    /// helper functions to lookup constants
    pub fn utf8(this: *const This, index: usize) []U1 {
        return this.constantPool[index].as(ConstantInfo.Utf8Info).bytes;
    }

    pub fn nameAndType(this: *const This, nameAndTypeIndex: usize) [2][]U1 {
        const nt = this.constantPool[nameAndTypeIndex].as(ConstantInfo.NameAndTypeInfo);
        return [_]U1{ this.utf8(nt.nameIndex), this.utf8(nt.descriptorIndex) };
    }
};

const ConstantTag = enum(U1) {
    class = 7,
    fieldref = 9,
    methodref = 10,
    interfaceMethodref = 11,
    string = 8,
    integer = 3,
    float = 4,
    long = 5,
    double = 6,
    nameAndType = 12,
    utf8 = 1,
    methodHandle = 15,
    methodType = 16,
    invokeDynamic = 18,
};

const ConstantInfo = union(ConstantTag) {
    class: ClassInfo,
    fieldref: FieldrefInfo,
    methodref: MethodrefInfo,
    interfaceMethodref: InterfaceMethodrefInfo,
    string: StringInfo,
    integer: IntegerInfo,
    float: FloatInfo,
    long: LongInfo,
    double: DoubleInfo,
    nameAndType: NameAndTypeInfo,
    utf8: Utf8Info,
    methodHandle: MethodHandleInfo,
    methodType: MethodTypeInfo,
    invokeDynamic: InvokeDynamicInfo,

    const This = @This();
    fn read(reader: *Reader) This {
        const tag: ConstantTag = @enumFromInt(reader.peek1());

        return switch (tag) {
            .class => .{ .class = ClassInfo.read(reader) },
            .fieldref => .{ .fieldref = FieldrefInfo.read(reader) },
            .methodref => .{ .methodref = MethodrefInfo.read(reader) },
            .interfaceMethodref => .{ .interfaceMethodref = InterfaceMethodrefInfo.read(reader) },
            .string => .{ .string = StringInfo.read(reader) },
            .integer => .{ .integer = IntegerInfo.read(reader) },
            .float => .{ .float = FloatInfo.read(reader) },
            .long => .{ .long = LongInfo.read(reader) },
            .double => .{ .double = DoubleInfo.read(reader) },
            .nameAndType => .{ .nameAndType = NameAndTypeInfo.read(reader) },
            .utf8 => .{ .utf8 = Utf8Info.read(reader) },
            .methodType => .{ .methodType = MethodTypeInfo.read(reader) },
            .methodHandle => .{ .methodHandle = MethodHandleInfo.read(reader) },
            .invokeDynamic => .{ .invokeDynamic = InvokeDynamicInfo.read(reader) },
        };
    }

    pub fn as(this: *const This, comptime T: type) T {
        return switch (this) {
            inline else => |t| if (@TypeOf(t) == T) t else unreachable,
        };
    }

    const ClassInfo = packed struct {
        tag: U1,
        nameIndex: U2,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .nameIndex = reader.read2() };
        }
    };

    const FieldrefInfo = packed struct {
        tag: U1,
        classIndex: U2,
        nameAndTypeIndex: U2,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .classIndex = reader.read2(), .nameAndTypeIndex = reader.read2() };
        }
    };

    const MethodrefInfo = packed struct {
        tag: U1,
        classIndex: U2,
        nameAndTypeIndex: U2,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .classIndex = reader.read2(), .nameAndTypeIndex = reader.read2() };
        }
    };

    const InterfaceMethodrefInfo = packed struct {
        tag: U1,
        classIndex: U2,
        nameAndTypeIndex: U2,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .classIndex = reader.read2(), .nameAndTypeIndex = reader.read2() };
        }
    };

    const StringInfo = packed struct {
        tag: U1,
        stringIndex: U2,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .stringIndex = reader.read2() };
        }
    };

    const IntegerInfo = packed struct {
        tag: U1,
        bytes: U4,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .bytes = reader.read4() };
        }

        pub fn value(this: *const @This()) i32 {
            return @bitCast(this.bytes);
        }
    };

    const FloatInfo = packed struct {
        tag: U1,
        bytes: U4,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .bytes = reader.read4() };
        }

        pub fn value(this: *const @This()) f32 {
            return @bitCast(this.bytes);
        }
    };

    const LongInfo = packed struct {
        tag: U1,
        highBytes: U4,
        lowBytes: U4,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .highBytes = reader.read4(), .lowBytes = reader.read4() };
        }

        pub fn value(this: *const @This()) i64 {
            const hi: u64 = this.highBytes;
            const lo: u64 = this.lowBytes;
            return @bitCast(hi << 32 | lo);
        }
    };

    const DoubleInfo = packed struct {
        tag: U1,
        highBytes: U4,
        lowBytes: U4,

        fn read(reader: *Reader) @This() {
            return .{
                .tag = reader.read1(),
                .highBytes = reader.read4(),
                .lowBytes = reader.read4(),
            };
        }

        pub fn value(this: *const @This()) f64 {
            const hi: u64 = this.highBytes;
            const lo: u64 = this.lowBytes;
            return @bitCast(hi << 32 | lo);
        }
    };

    const NameAndTypeInfo = packed struct {
        tag: U1,
        nameIndex: U2,
        descriptorIndex: U2,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .nameIndex = reader.read2(), .descriptorIndex = reader.read2() };
        }
    };

    const Utf8Info = struct {
        tag: U1,
        length: U2,
        bytes: []U1, //U2 length

        fn read(reader: *Reader) @This() {
            const tag = reader.read1();
            const length = reader.read2();
            return .{ .tag = tag, .length = length, .bytes = reader.read1s(length) };
        }
    };

    const MethodHandleInfo = packed struct {
        tag: U1,
        referenceKind: U1,
        referenceIndex: U2,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .referenceKind = reader.read1(), .referenceIndex = reader.read2() };
        }
    };

    const MethodTypeInfo = packed struct {
        tag: U1,
        descriptorIndex: U2,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .descriptorIndex = reader.read2() };
        }
    };

    const InvokeDynamicInfo = packed struct {
        tag: U1,
        bootstrapMethodAttrIndex: U2,
        nameAndTypeIndex: U2,

        fn read(reader: *Reader) @This() {
            return .{ .tag = reader.read1(), .bootstrapMethodAttrIndex = reader.read2(), .nameAndTypeIndex = reader.read2() };
        }
    };
};

const FieldInfo = struct {
    accessFlags: U2,
    nameIndex: U2,
    descriptorIndex: U2,
    attributeCount: U2,
    attributes: []AttributeInfo,

    const This = @This();
    fn read(reader: *Reader) This {
        const accessFlags = reader.read2();
        const nameIndex = reader.read2();
        const descriptorIndex = reader.read2();
        const attributeCount = reader.read2();
        const attributes = reader.reads(AttributeInfo, attributeCount, AttributeInfo.read);
        return .{ .accessFlags = accessFlags, .nameIndex = nameIndex, .descriptorIndex = descriptorIndex, .attributeCount = attributeCount, .attributes = attributes };
    }
};

const MethodInfo = struct {
    accessFlags: U2,
    nameIndex: U2,
    descriptorIndex: U2,
    attributeCount: U2,
    attributes: []AttributeInfo,

    const This = @This();
    fn read(reader: *Reader) This {
        const accessFlags = reader.read2();
        const nameIndex = reader.read2();
        const descriptorIndex = reader.read2();
        const attributeCount = reader.read2();
        const attributes = reader.reads(AttributeInfo, attributeCount, AttributeInfo.read);
        return .{ .accessFlags = accessFlags, .nameIndex = nameIndex, .descriptorIndex = descriptorIndex, .attributeCount = attributeCount, .attributes = attributes };
    }
};

const AttributeInfo = union(enum) {
    code: CodeAttribute,
    lineNumberTable: LineNumberTableAttribute,
    localVariableTable: LocalVariableTableAttribute,
    sourceFile: SourceFileAttribute,
    runtimeVisibleAnnotations: RuntimeVisibleAnnotationsAttribute,
    unsupported: UnsupportedAttribute,

    const This = @This();
    fn read(reader: *Reader) This {
        const attributeNameIndex = reader.peek2();
        const name = reader.lookup(ConstantInfo.Utf8Info, attributeNameIndex).bytes;
        if (std.mem.eql(U1, name, "Code")) {
            return .{ .code = CodeAttribute.read(reader) };
        }
        if (std.mem.eql(U1, name, "LineNumberTable")) {
            return .{ .lineNumberTable = LineNumberTableAttribute.read(reader) };
        }
        if (std.mem.eql(U1, name, "LocalVariableTable")) {
            return .{ .localVariableTable = LocalVariableTableAttribute.read(reader) };
        }
        if (std.mem.eql(U1, name, "SourceFile")) {
            return .{ .sourceFile = SourceFileAttribute.read(reader) };
        }
        if (std.mem.eql(U1, name, "RuntimeVisibleAnnotations")) {
            return .{ .runtimeVisibleAnnotations = RuntimeVisibleAnnotationsAttribute.read(reader) };
        }
        std.debug.print("Unsupported attribute {s}\n", .{name});
        return .{ .unsupported = UnsupportedAttribute.read(reader) };
    }

    const UnsupportedAttribute = struct {
        attributeNameIndex: U2,
        attributeLength: U4,
        raw: []U1,

        fn read(reader: *Reader) @This() {
            const attributeNameIndex = reader.read2();
            const attributeLength = reader.read4();
            return .{ .attributeNameIndex = attributeNameIndex, .attributeLength = attributeLength, .raw = reader.read1s(attributeLength) };
        }
    };

    const CodeAttribute = struct {
        attributeNameIndex: U2,
        attributeLength: U4,
        maxStack: U2,
        maxLocals: U2,
        codeLength: U4,
        code: []U1, //U4 code_length
        exceptionTableLength: U2,
        exceptionTable: []ExceptionTableEntry, //U2 exception_table_length
        attributesCount: U2,
        attributes: []AttributeInfo, //U2 attributes_count

        const ExceptionTableEntry = packed struct {
            startPc: U2,
            endPc: U2,
            handlerPc: U2,
            catchType: U2,

            fn read(reader: *Reader) @This() {
                return .{ .startPc = reader.read2(), .endPc = reader.read2(), .handlerPc = reader.read2(), .catchType = reader.read2() };
            }
        };

        fn read(reader: *Reader) @This() {
            const attributeNameIndex = reader.read2();
            const attributeLength = reader.read4();
            const maxStack = reader.read2();
            const maxLocals = reader.read2();
            const codeLength = reader.read4();
            const code = reader.read1s(codeLength);
            const exceptionTableLength = reader.read2();
            const exceptionTable = reader.reads(ExceptionTableEntry, exceptionTableLength, ExceptionTableEntry.read);
            const attributesCount = reader.read2();
            const attributes = reader.reads(AttributeInfo, attributesCount, AttributeInfo.read);
            return .{ .attributeNameIndex = attributeNameIndex, .attributeLength = attributeLength, .maxStack = maxStack, .maxLocals = maxLocals, .codeLength = codeLength, .code = code, .exceptionTableLength = exceptionTableLength, .exceptionTable = exceptionTable, .attributesCount = attributesCount, .attributes = attributes };
        }
    };

    const LineNumberTableAttribute = struct {
        attributeNameIndex: U2,
        attributeLength: U4,
        lineNumberTableLength: U2,
        lineNumberTable: []LineNumberTableEntry,

        const LineNumberTableEntry = packed struct {
            startPc: U2,
            lineNumber: U2,

            fn read(reader: *Reader) @This() {
                return .{ .startPc = reader.read2(), .lineNumber = reader.read2() };
            }
        };

        fn read(reader: *Reader) @This() {
            const attributeNameIndex = reader.read2();
            const attributeLength = reader.read4();
            const lineNumberTableLength = reader.read2();
            const lineNumberTable = reader.reads(LineNumberTableEntry, lineNumberTableLength, LineNumberTableEntry.read);
            return .{ .attributeNameIndex = attributeNameIndex, .attributeLength = attributeLength, .lineNumberTableLength = lineNumberTableLength, .lineNumberTable = lineNumberTable };
        }
    };

    const LocalVariableTableAttribute = struct {
        attributeNameIndex: U2,
        attributeLength: U4,
        localVariableTableLength: U2,
        localVariableTable: []LocalVariableTableEntry,

        const LocalVariableTableEntry = packed struct {
            startPc: U2,
            length: U2,
            nameIndex: U2,
            descriptorIndex: U2,
            index: U2,

            fn read(reader: *Reader) @This() {
                return .{ .startPc = reader.read2(), .length = reader.read2(), .nameIndex = reader.read2(), .descriptorIndex = reader.read2(), .index = reader.read2() };
            }
        };

        fn read(reader: *Reader) @This() {
            const attributeNameIndex = reader.read2();
            const attributeLength = reader.read4();
            const localVariableTableLength = reader.read2();
            const localVariableTable = reader.reads(LocalVariableTableEntry, localVariableTableLength, LocalVariableTableEntry.read);
            return .{ .attributeNameIndex = attributeNameIndex, .attributeLength = attributeLength, .localVariableTableLength = localVariableTableLength, .localVariableTable = localVariableTable };
        }
    };

    const SourceFileAttribute = packed struct {
        attributeNameIndex: U2,
        attributeLength: U4,
        sourceFileIndex: U2,

        fn read(reader: *Reader) @This() {
            return .{ .attributeNameIndex = reader.read2(), .attributeLength = reader.read4(), .sourceFileIndex = reader.read2() };
        }
    };

    const RuntimeVisibleAnnotationsAttribute = struct {
        attributeNameIndex: U2,
        attributeLength: U2,
        numAnnotations: U2,
        annotations: []Annotation,

        const Annotation = struct {
            typeIndex: U2,
            elementValuePairs: []ElementValuePair,
        };

        const ElementValuePair = struct {
            element_name_index: U2,
            value: ElementValue,
        };

        const ElementValue = struct {
            tag: U1,
            const_value_index: U2,
            enum_const_value: struct {
                type_name_index: U2,
                const_name_index: U2,
            },
            class_info_index: U2,
            array_value: struct {
                num_values: U2,
                values: []ElementValue,
            },
        };

        fn read(reader: *Reader) @This() {
            _ = reader;
            unreachable;
        }
    };
};
