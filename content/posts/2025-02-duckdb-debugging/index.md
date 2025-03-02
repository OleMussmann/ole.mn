---
date: 2025-02-15
title: "A debugging journey into the unknown"
summary: "We go through the steps I had to go through to debug a build problem with DuckDB, and in the process learn some concepts and techniques."
description: "An account of debugging a subtle build problem with DuckDB"
tags: ["Windows", "DLL", "DuckDB", "MingW", "cross-compilation", "git-bisect", "Julia", "BinaryBuilder"]
author: ["Suvayu Ali", "https://github.com/suvayu"]
issueLink = "https://github.com/suvayu/suvayu/issues"
---

![Among the Stars; Credit: NASA/JPL-Caltech](./pia17049-hires-cropped.jpg "Among the Stars; an artist's concept of Voyager in deep space")

# A debugging journey into the unknown

{{</* notice note */>}}
The story isn't complete.  There will be a concluding part when I actually fix the problem.
{{</* /notice */>}}

It all started with a colleague trying to update their Julia
environment for one of our projects[^1].  They could not update
because a dependency, the Julia bindings for DuckDB, was failing to
compile!  For the moment we decided to deal with it later, and pinned
`DuckDB.jl` to the working version.  We also filed an issue upstream:
[duckdb/duckdb#13911](https://github.com/duckdb/duckdb/issues/13911).

Since there was no significant progress on the issue for a few months,
I decided to dive in once and for all - this is that story.

## The issue

On Windows, trying to install any version of `DuckDB.jl` later than
`1.0.0` was failing with the error:

```julia
ERROR: LoadError: could not load symbol "duckdb_vector_size":
The specified procedure could not be found.
```

Some Julia packages, like `DuckDB.jl` depend on a native library.  The
native library is an internal dependency, and typically named
`MyPackage_jll.jl`; in the case of DuckDB, it is `DuckDB_jll.jl`.  The
error above tells us that during the compilation step, Julia tries to
load a symbol from the native library, but cannot find it.  A "symbol"
here refers to a DuckDB C-API function provided by the native DuckDB
library.

So as a first step, I wanted to check, can we actually install this
library, and load that symbol.  To get the call syntax correct, I
looked at the source code of [`DuckDB.jl`
](https://github.com/duckdb/duckdb/blob/5f5512b827df6397afd31daedb4bbdee76520019/tools/juliapkg/src/api.jl#L1285-L1297):

```julia
function duckdb_vector_size()
    return ccall((:duckdb_vector_size, libduckdb), idx_t, ())
end
```

TThe variable `idx_t` above is defined in `ctypes.jl` as:

```julia
const idx_t = UInt64 # DuckDB index type
```

So we can test loading the native library like this:

```julia
pkg] add DuckDB_jll
julia> using DuckDB_jll
ccall((:duckdb_vector_size, libduckdb), UInt64, ())
```

The above recipe replicates the error for any version newer than
`1.0.0`!  Hurray!  Now that we have confirmation that the problem is
in the native library, we have to understand: *Why is the symbol not
visible to Julia?*

## Symbol visibility in Windows DLLs

My first hurdle was to find a way to get both versions of the library
and compare.  I decided to install different versions of the native
library `DuckDB_jll` in different directories; after loading the
library, the `libduckdb` variable would point to the correct path.  We
can then use other tools to inspect the [dynamic-link
libraries](https://en.wikipedia.org/wiki/Dynamic-link_library) (DLLs)
and check if the symbols actually exist.  If we can compare the
working version of the native library with a version that does not
maybe we can find out what is wrong.

On Linux, we can use `nm` from `binutils` to look at the symbols
present in the library.  Thanks to the `-C` flag, `nm` can even
"demangle"[^2] symbol names if necessary.  So for the moment we can
copy over DLLs from Windows to Linux, and inspect.

```shell
$ nm -C libduckdb.dll | grep duckdb_vector_size  # working version: v1.0.0
000000036a271d00 T duckdb_vector_size
$ nm -C libduckdb.dll | grep duckdb_vector_size  # not working version: e.g. v1.1.2
000000036a36e0e0 T duckdb_vector_size
000000036be998d0 r .rdata$.refptr.duckdb_vector_size
000000036be998d0 R .refptr.duckdb_vector_size
```

No luck :frowning:, seems that the symbols exist for both versions of
the native library.  I was puzzled.  Searching around I found while
building Windows DLLs, you have to explicitly [export symbol
names](https://learn.microsoft.com/en-us/cpp/build/exporting-from-a-dll-using-declspec-dllexport)
using the `__declspec(dllexport)` attribute.  Besides signalling which
names are available, it also serves as a mechanism to optimise DLL
load times.  So I went looking for these attributes in the DuckDB
[source
code](https://github.com/duckdb/duckdb/blob/5f5512b827df6397afd31daedb4bbdee76520019/src/include/duckdb.h#L17-L31):

```c++
#ifndef DUCKDB_API
#ifdef _WIN32
#ifdef DUCKDB_STATIC_BUILD
#define DUCKDB_API
#else
#if defined(DUCKDB_BUILD_LIBRARY) && !defined(DUCKDB_BUILD_LOADABLE_EXTENSION)
#define DUCKDB_API __declspec(dllexport)
#else
#define DUCKDB_API __declspec(dllimport)
#endif
#endif
#else
#define DUCKDB_API
#endif
#endif
```

You can see, the `#ifdef` directives conditionally defines the macro
`DUCKDB_API` which expands to `__declspec(dllexport)` when building a
Windows DLL.  Later in the header file, this macro is used to [mark
every C-API function for
export](https://github.com/duckdb/duckdb/blob/5f5512b827df6397afd31daedb4bbdee76520019/src/include/duckdb.h#L1289-L1295).

```c++
DUCKDB_API idx_t duckdb_vector_size();
```

Now that we know the C-API function name symbols are marked for export
correctly, we should check if they are indeed exported.  After some
searching, I learnt Windows development tools includes the program
`dumpbin.exe` that can show the exported symbol names.

<details><summary>Exported symbols for the working version of <code>libduckdb.dll</code></summary>

```pwsh
> dumpbin.exe /EXPORTS .\bin\libduckdb.dll

Microsoft (R) COFF/PE Dumper Version 14.42.34435.0
Copyright (C) Microsoft Corporation.  All rights reserved.


Dump of file .\bin\libduckdb.dll

File Type: DLL

  Section contains the following exports for libduckdb.dll

    00000000 characteristics
           0 time date stamp
        0.00 version
           1 ordinal base
         335 number of functions
         335 number of names

    ordinal hint RVA      name

          1    0 004372E0 AdbcConnectionCancel
          2    1 00437320 AdbcConnectionCommit
          3    2 00437360 AdbcConnectionGetInfo
          4    3 00437470 AdbcConnectionGetObjects
          5    4 0043ACF0 AdbcConnectionGetOption
          6    5 0043AE40 AdbcConnectionGetOptionBytes
          7    6 0043B1E0 AdbcConnectionGetOptionDouble
          8    7 0043B020 AdbcConnectionGetOptionInt
          9    8 00437740 AdbcConnectionGetStatisticNames
         10    9 004375E0 AdbcConnectionGetStatistics
         11    A 00437840 AdbcConnectionGetTableSchema
         12    B 004378A0 AdbcConnectionGetTableTypes
         13    C 00439000 AdbcConnectionInit
         14    D 004379A0 AdbcConnectionNew
         15    E 00437AD0 AdbcConnectionReadPartition
         16    F 00438CA0 AdbcConnectionRelease
         17   10 00437BE0 AdbcConnectionRollback
         18   11 0043B5B0 AdbcConnectionSetOption
         19   12 0043B6E0 AdbcConnectionSetOptionBytes
         20   13 0043BB30 AdbcConnectionSetOptionDouble
         21   14 0043B980 AdbcConnectionSetOptionInt
         22   15 0043AAF0 AdbcDatabaseGetOption
         23   16 0043AC20 AdbcDatabaseGetOptionBytes
         24   17 0043B150 AdbcDatabaseGetOptionDouble
         25   18 0043AF90 AdbcDatabaseGetOptionInt
         26   19 0043F9C0 AdbcDatabaseInit
         27   1A 00437200 AdbcDatabaseNew
         28   1B 00438E20 AdbcDatabaseRelease
         29   1C 0043B310 AdbcDatabaseSetOption
         30   1D 0043B440 AdbcDatabaseSetOptionBytes
         31   1E 0043BA90 AdbcDatabaseSetOptionDouble
         32   1F 0043B8E0 AdbcDatabaseSetOptionInt
         33   20 004372C0 AdbcDriverManagerDatabaseSetInitFunc
         34   21 004371B0 AdbcErrorFromArrayStream
         35   22 00437150 AdbcErrorGetDetail
         36   23 00437120 AdbcErrorGetDetailCount
         37   24 0043F450 AdbcLoadDriver
         38   25 00438370 AdbcLoadDriverFromInitFunc
         39   26 00437C20 AdbcStatementBind
         40   27 00437C60 AdbcStatementBindStream
         41   28 00437CA0 AdbcStatementCancel
         42   29 00437CE0 AdbcStatementExecutePartitions
         43   2A 00437D30 AdbcStatementExecuteQuery
         44   2B 00437E30 AdbcStatementExecuteSchema
         45   2C 00437E70 AdbcStatementGetOption
         46   2D 00437EC0 AdbcStatementGetOptionBytes
         47   2E 00437F50 AdbcStatementGetOptionDouble
         48   2F 00437F10 AdbcStatementGetOptionInt
         49   30 00437F90 AdbcStatementGetParameterSchema
         50   31 00437FD0 AdbcStatementNew
         51   32 00438030 AdbcStatementPrepare
         52   33 00438070 AdbcStatementRelease
         53   34 004380C0 AdbcStatementSetOption
         54   35 00438100 AdbcStatementSetOptionBytes
         55   36 00438190 AdbcStatementSetOptionDouble
         56   37 00438150 AdbcStatementSetOptionInt
         57   38 004381D0 AdbcStatementSetSqlQuery
         58   39 00438210 AdbcStatementSetSubstraitPlan
         59   3A 00438250 AdbcStatusCodeMessage
         60   3B 0043EBC0 _Z34AdbcDriverManagerDefaultEntrypointRKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
         61   3C 015C5160 _ZN6duckdb7Catalog29CheckAmbiguousCatalogOrSchemaERNS_13ClientContextERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
         62   3D 015F0FF0 _ZN6duckdb9ErrorData10RawMessageB5cxx11Ev
         63   3E 016CC950 _ZNK6duckdb7Catalog21CatalogTypeLookupRuleENS_11CatalogTypeE
         64   3F 016CC980 _ZNK6duckdb9Extension7VersionB5cxx11Ev
         65   40 004358D0 duckdb_adbc_init
         66   41 007931C0 duckdb_add_replacement_scan
         67   42 007915B0 duckdb_append_blob
         68   43 00792570 duckdb_append_bool
         69   44 0078C340 duckdb_append_data_chunk
         70   45 00791B90 duckdb_append_date
         71   46 00791C50 duckdb_append_double
         72   47 00791D10 duckdb_append_float
         73   48 007921A0 duckdb_append_hugeint
         74   49 007923F0 duckdb_append_int16
         75   4A 00792330 duckdb_append_int32
         76   4B 00792270 duckdb_append_int64
         77   4C 007924B0 duckdb_append_int8
         78   4D 00791940 duckdb_append_interval
         79   4E 00791890 duckdb_append_null
         80   4F 00791AD0 duckdb_append_time
         81   50 00791A10 duckdb_append_timestamp
         82   51 00791DD0 duckdb_append_uhugeint
         83   52 00792020 duckdb_append_uint16
         84   53 00791F60 duckdb_append_uint32
         85   54 00791EA0 duckdb_append_uint64
         86   55 007920E0 duckdb_append_uint8
         87   56 007917D0 duckdb_append_varchar
         88   57 007916E0 duckdb_append_varchar_length
         89   58 0078C160 duckdb_appender_begin_row
         90   59 0078C2F0 duckdb_appender_close
         91   5A 0078C300 duckdb_appender_column_count
         92   5B 007955C0 duckdb_appender_column_type
         93   5C 0078BEC0 duckdb_appender_create
         94   5D 0078C0C0 duckdb_appender_destroy
         95   5E 0078C170 duckdb_appender_end_row
         96   5F 0078C140 duckdb_appender_error
         97   60 0078C230 duckdb_appender_flush
         98   61 0078D810 duckdb_array_type_array_size
         99   62 0078D7B0 duckdb_array_type_child_type
        100   63 0078C980 duckdb_array_vector_get_child
        101   64 00795C90 duckdb_arrow_array_scan
        102   65 007913C0 duckdb_arrow_column_count
        103   66 007913F0 duckdb_arrow_row_count
        104   67 00795D20 duckdb_arrow_rows_changed
        105   68 007958C0 duckdb_arrow_scan
        106   69 00792F50 duckdb_bind_add_result_column
        107   6A 00794CB0 duckdb_bind_blob
        108   6B 00794470 duckdb_bind_boolean
        109   6C 00794970 duckdb_bind_date
        110   6D 00794C20 duckdb_bind_decimal
        111   6E 00794910 duckdb_bind_double
        112   6F 007948B0 duckdb_bind_float
        113   70 0078E2B0 duckdb_bind_get_extra_info
        114   71 0078E300 duckdb_bind_get_named_parameter
        115   72 00794F60 duckdb_bind_get_parameter
        116   73 0078E2D0 duckdb_bind_get_parameter_count
        117   74 00794650 duckdb_bind_hugeint
        118   75 00794530 duckdb_bind_int16
        119   76 00794590 duckdb_bind_int32
        120   77 007945F0 duckdb_bind_int64
        121   78 007944D0 duckdb_bind_int8
        122   79 00794A90 duckdb_bind_interval
        123   7A 00794D10 duckdb_bind_null
        124   7B 00790B30 duckdb_bind_parameter_index
        125   7C 0078E430 duckdb_bind_set_bind_data
        126   7D 0078E450 duckdb_bind_set_cardinality
        127   7E 0078E4C0 duckdb_bind_set_error
        128   7F 007949D0 duckdb_bind_time
        129   80 00794A30 duckdb_bind_timestamp
        130   81 007946C0 duckdb_bind_uhugeint
        131   82 00794790 duckdb_bind_uint16
        132   83 007947F0 duckdb_bind_uint32
        133   84 00794850 duckdb_bind_uint64
        134   85 00794730 duckdb_bind_uint8
        135   86 00793CE0 duckdb_bind_value
        136   87 00794AF0 duckdb_bind_varchar
        137   88 00794B60 duckdb_bind_varchar_length
        138   89 0078DDF0 duckdb_clear_bindings
        139   8A 0078CD70 duckdb_close
        140   8B 00790790 duckdb_column_count
        141   8C 00796F60 duckdb_column_data
        142   8D 00795440 duckdb_column_logical_type
        143   8E 00795650 duckdb_column_name
        144   8F 00795510 duckdb_column_type
        145   90 0078C590 duckdb_config_count
        146   91 0078FFB0 duckdb_connect
        147   92 0078D470 duckdb_create_array_type
        148   93 0078F4F0 duckdb_create_array_value
        149   94 0078C4B0 duckdb_create_config
        150   95 0078EF40 duckdb_create_data_chunk
        151   96 0078D510 duckdb_create_decimal_type
        152   97 0078E820 duckdb_create_enum_type
        153   98 0078CF90 duckdb_create_int64
        154   99 0078D3E0 duckdb_create_list_type
        155   9A 0078F300 duckdb_create_list_value
        156   9B 0078D390 duckdb_create_logical_type
        157   9C 0078EE40 duckdb_create_map_type
        158   9D 007927B0 duckdb_create_struct_type
        159   9E 0078F110 duckdb_create_struct_value
        160   9F 0078ECA0 duckdb_create_table_function
        161   A0 00793310 duckdb_create_task_state
        162   A1 0078CBF0 duckdb_create_time_tz
        163   A2 00792AD0 duckdb_create_union_type
        164   A3 0078CF00 duckdb_create_varchar
        165   A4 0078CE70 duckdb_create_varchar_length
        166   A5 0078C760 duckdb_data_chunk_get_column_count
        167   A6 0078C790 duckdb_data_chunk_get_size
        168   A7 007951A0 duckdb_data_chunk_get_vector
        169   A8 0078C740 duckdb_data_chunk_reset
        170   A9 0078C7B0 duckdb_data_chunk_set_size
        171   AA 0078D620 duckdb_decimal_internal_type
        172   AB 0078D600 duckdb_decimal_scale
        173   AC 0078D310 duckdb_decimal_to_double
        174   AD 0078D5E0 duckdb_decimal_width
        175   AE 0078C410 duckdb_destroy_arrow
        176   AF 0078C470 duckdb_destroy_arrow_stream
        177   B0 0078C6C0 duckdb_destroy_config
        178   B1 0078C700 duckdb_destroy_data_chunk
        179   B2 0078DE90 duckdb_destroy_extracted
        180   B3 0078D5A0 duckdb_destroy_logical_type
        181   B4 0078DB00 duckdb_destroy_pending
        182   B5 0078DF20 duckdb_destroy_prepare
        183   B6 0078E060 duckdb_destroy_result
        184   B7 0078E190 duckdb_destroy_table_function
        185   B8 0078E710 duckdb_destroy_task_state
        186   B9 0078CE30 duckdb_destroy_value
        187   BA 0078CDE0 duckdb_disconnect
        188   BB 0078EC20 duckdb_double_to_decimal
        189   BC 0078D250 duckdb_double_to_hugeint
        190   BD 0078D2B0 duckdb_double_to_uhugeint
        191   BE 00794DA0 duckdb_enum_dictionary_size
        192   BF 0078D6C0 duckdb_enum_dictionary_value
        193   C0 0078D680 duckdb_enum_internal_type
        194   C1 0078E6D0 duckdb_execute_n_tasks_state
        195   C2 007904F0 duckdb_execute_pending
        196   C3 00790E60 duckdb_execute_prepared
        197   C4 00791280 duckdb_execute_prepared_arrow
        198   C5 00790D70 duckdb_execute_prepared_streaming
        199   C6 00793390 duckdb_execute_tasks
        200   C7 0078E690 duckdb_execute_tasks_state
        201   C8 007939F0 duckdb_execution_is_finished
        202   C9 0078DBD0 duckdb_extract_statements
        203   CA 0078DDD0 duckdb_extract_statements_error
        204   CB 007900D0 duckdb_fetch_chunk
        205   CC 0078F8A0 duckdb_finish_execution
        206   CD 0078D1A0 duckdb_free
        207   CE 0078CA90 duckdb_from_date
        208   CF 0078CB20 duckdb_from_time
        209   D0 0078CB80 duckdb_from_time_tz
        210   D1 0078CC40 duckdb_from_timestamp
        211   D2 0078E5F0 duckdb_function_get_bind_data
        212   D3 0078E5D0 duckdb_function_get_extra_info
        213   D4 0078E610 duckdb_function_get_init_data
        214   D5 0078E630 duckdb_function_get_local_init_data
        215   D6 0078E650 duckdb_function_set_error
        216   D7 0078C5A0 duckdb_get_config_flag
        217   D8 0078D0B0 duckdb_get_int64
        218   D9 0078D570 duckdb_get_type_id
        219   DA 0078D000 duckdb_get_varchar
        220   DB 0078D1D0 duckdb_hugeint_to_double
        221   DC 0078E520 duckdb_init_get_bind_data
        222   DD 0078E5A0 duckdb_init_get_column_count
        223   DE 00794F10 duckdb_init_get_column_index
        224   DF 0078E500 duckdb_init_get_extra_info
        225   E0 0078E560 duckdb_init_set_error
        226   E1 0078E540 duckdb_init_set_init_data
        227   E2 0078E5C0 duckdb_init_set_max_threads
        228   E3 0078CDC0 duckdb_interrupt
        229   E4 0078CB00 duckdb_is_finite_date
        230   E5 0078CD40 duckdb_is_finite_timestamp
        231   E6 0078CE20 duckdb_library_version
        232   E7 0078D740 duckdb_list_type_child_type
        233   E8 0078C900 duckdb_list_vector_get_child
        234   E9 0078C920 duckdb_list_vector_get_size
        235   EA 0078C960 duckdb_list_vector_reserve
        236   EB 0078C940 duckdb_list_vector_set_size
        237   EC 0078DA20 duckdb_logical_type_get_alias
        238   ED 0078D190 duckdb_malloc
        239   EE 0078D830 duckdb_map_type_key_type
        240   EF 0078D890 duckdb_map_type_value_type
        241   F0 00790FA0 duckdb_nparams
        242   F1 00796FA0 duckdb_nullmask_data
        243   F2 0078EC10 duckdb_open
        244   F3 0078EA00 duckdb_open_ext
        245   F4 007933F0 duckdb_param_type
        246   F5 00792630 duckdb_parameter_name
        247   F6 0078DB50 duckdb_pending_error
        248   F7 0078FED0 duckdb_pending_execute_check_state
        249   F8 0078FDF0 duckdb_pending_execute_task
        250   F9 0078DB80 duckdb_pending_execution_is_finished
        251   FA 00790B10 duckdb_pending_prepared
        252   FB 00790B20 duckdb_pending_prepared_streaming
        253   FC 00790C30 duckdb_prepare
        254   FD 00790FF0 duckdb_prepare_error
        255   FE 00794FE0 duckdb_prepare_extracted_statement
        256   FF 00793530 duckdb_prepared_arrow_schema
        257  100 00790F50 duckdb_prepared_statement_type
        258  101 00790410 duckdb_query
        259  102 007914D0 duckdb_query_arrow
        260  103 00791040 duckdb_query_arrow_array
        261  104 00791390 duckdb_query_arrow_error
        262  105 00791440 duckdb_query_arrow_schema
        263  106 00793B30 duckdb_query_progress
        264  107 00793A30 duckdb_register_table_function
        265  108 0078F0C0 duckdb_replacement_scan_add_parameter
        266  109 0078E020 duckdb_replacement_scan_set_error
        267  10A 0078DFE0 duckdb_replacement_scan_set_function_name
        268  10B 007907D0 duckdb_result_arrow_array
        269  10C 007901C0 duckdb_result_chunk_count
        270  10D 00790640 duckdb_result_error
        271  10E 00790880 duckdb_result_get_chunk
        272  10F 007906A0 duckdb_result_is_streaming
        273  110 007906E0 duckdb_result_return_type
        274  111 00790740 duckdb_result_statement_type
        275  112 007902E0 duckdb_row_count
        276  113 00790220 duckdb_rows_changed
        277  114 0078C5F0 duckdb_set_config
        278  115 00790140 duckdb_stream_fetch_chunk
        279  116 0078D1C0 duckdb_string_is_inlined
        280  117 0078D8F0 duckdb_struct_type_child_count
        281  118 0078D9E0 duckdb_struct_type_child_name
        282  119 0078DAA0 duckdb_struct_type_child_type
        283  11A 00795150 duckdb_struct_vector_get_child
        284  11B 00793BB0 duckdb_table_function_add_named_parameter
        285  11C 0078F070 duckdb_table_function_add_parameter
        286  11D 0078E220 duckdb_table_function_set_bind
        287  11E 0078E200 duckdb_table_function_set_extra_info
        288  11F 0078E280 duckdb_table_function_set_function
        289  120 0078E240 duckdb_table_function_set_init
        290  121 0078E260 duckdb_table_function_set_local_init
        291  122 0078E1C0 duckdb_table_function_set_name
        292  123 0078E2A0 duckdb_table_function_supports_projection_pushdown
        293  124 0078F8F0 duckdb_task_state_is_finished
        294  125 0078CAD0 duckdb_to_date
        295  126 0078CC10 duckdb_to_time
        296  127 0078CCE0 duckdb_to_timestamp
        297  128 0078D210 duckdb_uhugeint_to_double
        298  129 0078D910 duckdb_union_type_member_count
        299  12A 0078D940 duckdb_union_type_member_name
        300  12B 0078D980 duckdb_union_type_member_type
        301  12C 0078C9A0 duckdb_validity_row_is_valid
        302  12D 0078CA30 duckdb_validity_set_row_invalid
        303  12E 0078CA60 duckdb_validity_set_row_valid
        304  12F 0078C9D0 duckdb_validity_set_row_validity
        305  130 0078E750 duckdb_value_blob
        306  131 00795430 duckdb_value_boolean
        307  132 00795260 duckdb_value_date
        308  133 00795330 duckdb_value_decimal
        309  134 00795270 duckdb_value_double
        310  135 00795280 duckdb_value_float
        311  136 00795300 duckdb_value_hugeint
        312  137 00795410 duckdb_value_int16
        313  138 00795400 duckdb_value_int32
        314  139 007953F0 duckdb_value_int64
        315  13A 00795420 duckdb_value_int8
        316  13B 00795200 duckdb_value_interval
        317  13C 0078E7E0 duckdb_value_is_null
        318  13D 00792760 duckdb_value_string
        319  13E 007956E0 duckdb_value_string_internal
        320  13F 00795250 duckdb_value_time
        321  140 00795240 duckdb_value_timestamp
        322  141 007952D0 duckdb_value_uhugeint
        323  142 007952B0 duckdb_value_uint16
        324  143 007952A0 duckdb_value_uint32
        325  144 00795290 duckdb_value_uint64
        326  145 007952C0 duckdb_value_uint8
        327  146 00792780 duckdb_value_varchar
        328  147 007957F0 duckdb_value_varchar_internal
        329  148 0078C860 duckdb_vector_assign_string_element
        330  149 0078C8C0 duckdb_vector_assign_string_element_len
        331  14A 00793090 duckdb_vector_ensure_validity_writable
        332  14B 0078C7C0 duckdb_vector_get_column_type
        333  14C 0078C810 duckdb_vector_get_data
        334  14D 0078C830 duckdb_vector_get_validity
        335  14E 0078D1B0 duckdb_vector_size

  Summary

        1000 .CRT
       12000 .bss
        F000 .data
        7000 .debug_abbrev
        1000 .debug_aranges
        3000 .debug_frame
       62000 .debug_info
        A000 .debug_line
       28000 .debug_loc
        2000 .debug_ranges
        1000 .debug_str
        3000 .edata
        5000 .idata
       81000 .pdata
      929000 .rdata
       16000 .reloc
     17E1000 .text
        1000 .tls
      17E000 .xdata
```
</details>

<details><summary>Exported symbols for a faulty version of <code>libduckdb.dll</code></summary>

```pwsh
> dumpbin.exe /EXPORTS .\bin\libduckdb.dll
Microsoft (R) COFF/PE Dumper Version 14.42.34435.0
Copyright (C) Microsoft Corporation.  All rights reserved.

Dump of file .\bin\libduckdb.dll

File Type: DLL

  Section contains the following exports for libduckdb.dll

    00000000 characteristics
           0 time date stamp
        0.00 version
           1 ordinal base
          82 number of functions
          82 number of names

    ordinal hint RVA      name

          1    0 00466E20 AdbcConnectionCancel
          2    1 00466E60 AdbcConnectionCommit
          3    2 00466EA0 AdbcConnectionGetInfo
          4    3 00466FB0 AdbcConnectionGetObjects
          5    4 0046A850 AdbcConnectionGetOption
          6    5 0046A9A0 AdbcConnectionGetOptionBytes
          7    6 0046AD40 AdbcConnectionGetOptionDouble
          8    7 0046AB80 AdbcConnectionGetOptionInt
          9    8 00467280 AdbcConnectionGetStatisticNames
         10    9 00467120 AdbcConnectionGetStatistics
         11    A 00467380 AdbcConnectionGetTableSchema
         12    B 004673E0 AdbcConnectionGetTableTypes
         13    C 00468B50 AdbcConnectionInit
         14    D 004674E0 AdbcConnectionNew
         15    E 00467610 AdbcConnectionReadPartition
         16    F 004687F0 AdbcConnectionRelease
         17   10 00467720 AdbcConnectionRollback
         18   11 0046B0A0 AdbcConnectionSetOption
         19   12 0046B1D0 AdbcConnectionSetOptionBytes
         20   13 0046B5B0 AdbcConnectionSetOptionDouble
         21   14 0046B400 AdbcConnectionSetOptionInt
         22   15 0046A650 AdbcDatabaseGetOption
         23   16 0046A780 AdbcDatabaseGetOptionBytes
         24   17 0046ACB0 AdbcDatabaseGetOptionDouble
         25   18 0046AAF0 AdbcDatabaseGetOptionInt
         26   19 0046FE80 AdbcDatabaseInit
         27   1A 00466D40 AdbcDatabaseNew
         28   1B 00468970 AdbcDatabaseRelease
         29   1C 0046AE70 AdbcDatabaseSetOption
         30   1D 0046AFA0 AdbcDatabaseSetOptionBytes
         31   1E 0046B510 AdbcDatabaseSetOptionDouble
         32   1F 0046B360 AdbcDatabaseSetOptionInt
         33   20 00466E00 AdbcDriverManagerDatabaseSetInitFunc
         34   21 00466CF0 AdbcErrorFromArrayStream
         35   22 00466C90 AdbcErrorGetDetail
         36   23 00466C60 AdbcErrorGetDetailCount
         37   24 0046F900 AdbcLoadDriver
         38   25 00467EB0 AdbcLoadDriverFromInitFunc
         39   26 00467760 AdbcStatementBind
         40   27 004677A0 AdbcStatementBindStream
         41   28 004677E0 AdbcStatementCancel
         42   29 00467820 AdbcStatementExecutePartitions
         43   2A 00467870 AdbcStatementExecuteQuery
         44   2B 00467970 AdbcStatementExecuteSchema
         45   2C 004679B0 AdbcStatementGetOption
         46   2D 00467A00 AdbcStatementGetOptionBytes
         47   2E 00467A90 AdbcStatementGetOptionDouble
         48   2F 00467A50 AdbcStatementGetOptionInt
         49   30 00467AD0 AdbcStatementGetParameterSchema
         50   31 00467B10 AdbcStatementNew
         51   32 00467B70 AdbcStatementPrepare
         52   33 00467BB0 AdbcStatementRelease
         53   34 00467C00 AdbcStatementSetOption
         54   35 00467C40 AdbcStatementSetOptionBytes
         55   36 00467CD0 AdbcStatementSetOptionDouble
         56   37 00467C90 AdbcStatementSetOptionInt
         57   38 00467D10 AdbcStatementSetSqlQuery
         58   39 00467D50 AdbcStatementSetSubstraitPlan
         59   3A 00467D90 AdbcStatusCodeMessage
         60   3B 0046F070 _Z34AdbcDriverManagerDefaultEntrypointRKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
         61   3C 011BBAB0 _ZN6duckdb14EncryptionUtilC1Ev
         62   3D 011BBAC0 _ZN6duckdb14EncryptionUtilC2Ev
         63   3E 01500A30 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeINS_10uhugeint_tEEERT_v
         64   3F 01500A40 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeINS_9hugeint_tEEERT_v
         65   40 01500A50 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeIaEERT_v
         66   41 01500A60 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeIbEERT_v
         67   42 01500A70 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeIdEERT_v
         68   43 01500A80 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeIfEERT_v
         69   44 01500A90 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeIhEERT_v
         70   45 01500AA0 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeIiEERT_v
         71   46 01500AB0 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeIjEERT_v
         72   47 01500AC0 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeIsEERT_v
         73   48 01500AD0 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeItEERT_v
         74   49 01500AE0 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeIxEERT_v
         75   4A 01500AF0 _ZN6duckdb17NumericValueUnion18GetReferenceUnsafeIyEERT_v
         76   4B 0177C5D0 _ZN6duckdb7Catalog17GetCatalogVersionERNS_13ClientContextE
         77   4C 0177C5E0 _ZN6duckdb7Catalog29CheckAmbiguousCatalogOrSchemaERNS_13ClientContextERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
         78   4D 018BFE90 _ZNK6duckdb7Catalog21CatalogTypeLookupRuleENS_11CatalogTypeE
         79   4E 018BFFE0 _ZNK6duckdb9ErrorData10RawMessageB5cxx11Ev
         80   4F 018BFFF0 _ZNK6duckdb9ErrorData7MessageB5cxx11Ev
         81   50 018C0000 _ZNK6duckdb9Extension7VersionB5cxx11Ev
         82   51 00464E50 duckdb_adbc_init

  Summary

        1000 .CRT
       12000 .bss
        F000 .data
        8000 .debug_abbrev
        1000 .debug_aranges
        3000 .debug_frame
       63000 .debug_info
        A000 .debug_line
       28000 .debug_loc
        2000 .debug_ranges
        1000 .debug_str
        1000 .edata
        5000 .idata
       8A000 .pdata
      9C2000 .rdata
       17000 .reloc
     19EB000 .text
        1000 .tls
      197000 .xdata
```
</details>

So it is confirmed that the symbol export is not working for the
faulty version.  However we still do not know which commit introduced
the issue.  Let us try to find that :slightly_smiling_face:.

## Hunt for the first "bad" commit

To be able to find the first bad commit, we need to be able to compile
the library.  Julia has a whole other infrastructure called
[`BinaryBuilder`](https://binarybuilder.org/).  It cross-compiles
native binaries for all platforms on Linux.  This is a whole another
rabbit hole, and let us shelve this for another time.  The only
relevant bit is, the builds are done *only* on Linux.  This presents a
different problem, `dumpbin.exe`, the tool to check if the symbol
export is correct is available only on Windows.  If we are to find the
bad commit, we need to automate the build & check steps and run it
with `git-bisect`.  How can we do that if parts of our toolchain runs
on different platforms‽

So I went searching again for an alternative.  Unsurprisingly, Wine
(the Windows compatibility layer for Linux) ships with the tool
[`winedump`](https://gitlab.winehq.org/wine/wine/-/wikis/Man-Pages/winedump),
which is an equivalent to the Windows tool `dumpbin.exe`.

To build the Windows DLL, we need to cross-compile DuckDB on Linux
using the MingW-w64 toolchain.  Combined with the `winedump` tool, I
wrote the following script that we can use to test a successful build.

```bash
#!/bin/bash

rm -rf build
cmake -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE=mingw-w64-x86_64.cmake \
      -DBUILD_EXTENSIONS='autocomplete;icu;parquet;json;fts;tpcds;tpch' \
      -DENABLE_EXTENSION_AUTOLOADING=1 \
      -DENABLE_EXTENSION_AUTOINSTALL=1 \
      -DBUILD_UNITTESTS=FALSE \
      -DBUILD_SHELL=TRUE \
      -DDUCKDB_EXPLICIT_PLATFORM=x86_64-w64-mingw32-cxx11 .
cmake --build build

[[ $? -ne 0 ]] && \
{
    echo "build failed, cannot test"
    exit 125
}

if [[ -f build/src/libduckdb.dll ]]; then
    winedump -j export build/src/libduckdb.dll | grep -q duckdb_vector_size
    if [[ $? -eq 0 ]]; then
	exit 0
    else
	exit 1
    fi
else
    echo "cannot find DLL, cannot test"
    exit 125
fi
```

The script builds DuckDB, and checks whether the generated DLL file
export the C-API symbols correctly.  It also handles a few corner
cases of build failures.  Note that the build command uses the
following toolchain file (thanks to this
[gist](https://gist.github.com/peterspackman/8cf73f7f12ba270aa8192d6911972fe8/)).

```cmake
set(CMAKE_SYSTEM_NAME Windows)
set(TOOLCHAIN_PREFIX x86_64-w64-mingw32)

# cross compilers to use for C, C++ and Fortran
set(CMAKE_C_COMPILER ${TOOLCHAIN_PREFIX}-gcc)
set(CMAKE_CXX_COMPILER ${TOOLCHAIN_PREFIX}-g++)
set(CMAKE_Fortran_COMPILER ${TOOLCHAIN_PREFIX}-gfortran)
set(CMAKE_RC_COMPILER ${TOOLCHAIN_PREFIX}-windres)

# target environment on the build host system
set(CMAKE_FIND_ROOT_PATH /usr/${TOOLCHAIN_PREFIX})

# modify default behavior of FIND_XXX() commands
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
```

Now we can use this script with `git-bisect` to find the first bad
commit, like this:

```bash
$ git bisect start
$ git bisect bad v1.1.2
$ git bisect good v1.0.0
$ git bisect run ./bisect-script.bash
$ git bisect visualize # shows a nice summary
$ git bisect reset

```

The bisection led me to this commit:
[d1ea1538](https://github.com/duckdb/duckdb/commit/d1ea1538c9217fb536485f1500f04a0b55b1e584).
Unfortunately it is not clear how that commit would lead to symbol
export failure, it only adds 11 new functions to the C-API (so 11 new
symbols).  So for now, this debugging journey has to stop here,
without a clear resolution.  But we did learn a lot of new concepts,
and used a wide variety of tools to investigate.

## What did we learn?

To summarise, the issue is:
1. All releases of `DuckDB.jl` after `v1.0.0` on Windows are broken.
2. We recreate the issue without Julia, which shows the the DuckDB
   build using the MingW-w64 toolchain is broken for all releases
   after `v1.0.0`.

And in the process of debugging this, we learnt:
1. Windows has a separate mechanism to export symbol names in its
   shared libraries (DLL).
2. We learnt about tools to inspect symbols in native libraries;
   namely `nm`, `dumpbin.exe`, and `winedump`.
3. We learnt about the Julia build system for native libraries (a
   topic for a future post).
4. We learnt to write a script that we can use with `git-bisect` to
   run automatic bisections (a potential topic for a future post).


[^1]: [Tulipa](https://github.com/TulipaEnergy)
[^2]: [Name mangling](https://en.wikipedia.org/wiki/Name_mangling)

{{< flourish 4 >}}

*Image Credit: [NASA/JPL-Caltech](https://science.nasa.gov/image-detail/pia17049-hires/)*

{{< flourish 8 >}}

*Cross-post from:* https://github.com/suvayu/suvayu/blob/master/blog/2025-02-15-duckdb-julia-windows.md
