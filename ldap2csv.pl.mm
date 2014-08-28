.TH LDAP2CSV.PL "1" "August 2014" "ldap2csv.pl 0.1.4" "User Commands"
.SH NAME
ldap2csv.pl \- Transfer ldap tree data to csv
.SH SYNOPSIS
ldap2csv.pl mode source [who] [what] [output]
.SH DESCRIPTION
.PP
The
.B ldap2csv.pl
try the best to cut short LDAP searching complication, and it could outputs csv format, so it is easy to work with grep, etc., classic UNIX tools.
In other words, you can use this tool and need not to know much about LDAP protocols and implements.
.PP
The
.B ldap2csv.pl
has
.I schema
,
.I probe
,
.I collect
, and
.I tree2csv
work modes. Some of these work modes except getting data from LDAP server, could treate files as data source and read data in from the files.
.PP
And it supports
.I LDIF
,
.I csv
, and
.I sql
output formats. LDIF is abbreviation of LDAP Data Interchange Format, which is a text format. The sql format will output SQL statements for
.B SQLite3
, will create a table in the main database. The table name is created by connecting each argument of \-\-is option or \-\-maybe option by
.B '_'
, but no more than 128 charaters, or will be cut. We always remove the last character of the table name if the character is '_'.
.
.PP
The
.B ldap2csv.pl
, uses UTF-8 as I/O encoding, and is case sensitive, while LDAP is not case sensitive. This feature appends some constraints for using this tool, especially when crossing work modes.  
.SH OPTIONS
.PP
At last a mode and a source option is needed.
.SS To select a mode:
.TP
\fB\-\-schema, schema\fR
Enalbe schema work mode, get LDAP schema from LDAP server or other data sources, then display the schema or output the schema to STDOUT or other files. Only support LDIF output format.
.TP
\fB\-\-probe, probe\fR
Persons, web servers, and printers, etc., in LDAP terms, are one of some objectclasses. This mode display all objectclasses names if no --is option,
or display some objectclasses details and the objectclasses' parent objectclasses details.
.TP
\fB\-\-collect, collect\fR
Enable collect work mode to collect some who's data, in LDAP terms, some objects' data, from LDAP server. This the default action.
.TP
\fB\-\-tree2csv, tree2csv\fR
Enable tree2csv work mode to transfer a tree to csv so shell can easily do more, and this mode will do rescursion, or just use collect work mode is enough.
.SS Modes shared options:
.PP
These options are shared by the above modes.
.TP
\fB\-\-csv\fR
Output csv. You can set separator as need.
.TP
\fB\-\-help\fR
Display this help page.
.TP
\fB\-\-ldif\fR
Output csv. You can set separator as need.
.TP
\fB\-\-output\fR
Output to a named file instead of to the stdout.
.TP
\fB\-\-separator\fR
Set the separator when output as csv format.
.TP
\fB\-\-source\fR
Set a file as data source. The file may be SQLite3 table, csv, or LDIF file. Not all work modes support this option.
.TP
\fB\-\-sql\fR
Ouput SQL statements that you can use to create a SQLite3 database. If there \-\-output option, will create a SQLite database for you.
.TP
\fB\-\-verbose\fR
Output verbosely or not. Has no effect now.
.TP
\fB\-\-version\fR
Show the program version, then quit.
.SS  The schema mode options:
.PP
The schema mode requires a source which could be an url or a LDIF file source. And the work mode only support LDIF output format.
.TP
\fB\-\-url\fR
Set LDAP url: schema://server:port, where schema could be one of ldap, ldaps, and ldapi. DO NOT think too much, we only support "ldap" and "ldaps" now. And we DO NOT completely support URLs as the ldapurl(1) does. Perhaps we
will support that in the future, while probably we will never do that.
.SS The probe mode options:
.PP
The probe mode requires a data source which could be a LDAP server or a LDIF file.
And it also could accepts an objectclass. If no objectclass, it will display all objectclasses names. Or it will display the given objectclasses detailed infos. The mode only support
LDIF output format (when given \-\-is option, the output format is what the dump function of the Perl Data::Dump module), and will output on STDOUT. So thie work mode does not support --output option.
.TP
\fB\-\-url\fR
Set LDAP url: schema://server:port, where schema could be one of ldap, ldaps, and ldapi. DO NOT think too much, we only support "ldap" and "ldaps" now. And we DO NOT completely support URLs as the ldapurl(1) does. Perhaps we
will support that in the future, while probably we will never do that.
.TP
\fB\-\-is\fR
It is the who that we will probe, or whose data we will search.
.SS The collect mode options:
The collect need LDAP server as data source, search some given objectclasses from the server, then display the results.
.TP
\fB\-\-url\fR
Set LDAP url: schema://server:port, where schema could be one of ldap, ldaps, and ldapi. DO NOT think too much, we only support "ldap" and "ldaps" now. And we DO NOT completely support URLs as the ldapurl(1) does. Perhaps we
will support that in the future, while probably we will never do that.
.TP
\fB\-\-is\fR
It is the who we will probe, or whose data we will search.
.TP
\fB\-\-maybe\fR
It may be the who that we will probe, or whose data we will search.
.TP
\fB\-\-relation\fR
The option gives the attributes that we want. And we will ouput the result as orders of the \-\-relation option orders.  
.SS The tree2csv mode options:
.PP
This work support csv and sql output formats. And the first \-\-realtion option argument should be given as the following formats:
.PP
.SB init_attr:init_attr_after_transfer:recur_attr:recur_attr_after_transfer
.PP
The tree2csv work mode initializes the init_set set by arguments of the \-\-init options, then scans the input source that given by --source option to check whethere the recur_attr of each init_attr is in the init_set.
If yes, then add the init_attr to the init_set. The tree2csv will do the above action until init_set size, in mathematics its cardinal number, does not change, then display the init_set elements and quit.
.PP
While a problem is, most of time you cannot directly add init_attr to the init_set, one of them may be a string, another is number. The same problem exists for recur_attr and init_set. So we need a 'middle' attribute that
we can transfer what need and have these attributes and init_set expressed in a universal way. That's why the first --relation need a long and some complicated argument.
.PP
The work mode only support csv and sql output formats.
.TP
\fB\-\-init\fR
Initialize the set from which we will add more as following the relations set by \-\-relation options.
.TP
\fB\-\-relation\fR
The first option set relations that we use it to do rescursion to transfer a tree to csv, and others gives the attributes that we want. And we will ouput the result as orders of the \-\-relation option orders.  
.SS About SSL options:
.PP
The default action is that we do not verify LDAP servers certificates because it is most possible that LDAP servers use self-signed certificates.
.TP
\fB\-\-cafile\fR
Set the path to the CA certificate. You need this if you want to verify the server certificate, the mean while the LDAP server uses a self-signed certificate.
.TP
\fB\-\-verify\fR
Whether verify LDAP server SSL certificate. Default is not to.
.SS Output formats:
.PP
When enable sql output format, you can use \-\-output set the output file name, while the the table name is created by connecting arguments of \-\-is options or --maybe options. And we also make sure that
the table name is not more than 128 characters, and the last charater is not
.B _
.
We always created table in the
\B main
database. And what we do in detail is, first, drop table, then create table, then insert data. It's recommend to always use a new, specialized file as output file, so we can avoid filesystem and SQLite3 locks.
.PP
We remove objecClass attribute when output sql or csv format in
.BI collect
work mode. If you need that attribute, please use \-\-relation option. It's some boring if you really need such attribute, right? While, I think, OK, I guess, most of people needn't that attribute. So, I'm sorry.
.PP
When output csv format, the first line is the attributes that output, so you should skip the first line if you need not.
.SS Exit status:
.PP
It is shame to say that my program has no useful exit code for you, but it is real. So, you need check the output, the output file, etc., to make sure you successfully do something or not.
.SH Examples:
.PP
To use the LDAP data, it's better to get the LDAP
.BI schema
first. Even you don't know much about ASN and LDAP schema, most of object classes names and attribute names are useful. Then you can get all the object classes names by
the
.BI probe
work mode, after that you can by the same mode to get the details of some object classes that you're interested. First perhaps you will
.BI collect
all the attributes and values of some object classes, while, possible
that most of the attributes have no value. So when you make you problems clear, you will only collect some object classes' some attributes.
.PP
Hence SQLite's SELECT statement supports recursion, tell the truth, we don't really need the
.BI tree2csv
work mode. While, if we are lazy (that's true, we are always lazy), or we don't like SQL, this work mode will help, right?
.IP
ldap2csv.pl \fB\-\-help\fR
.IP
ldap2csv.pl \fBprobe\fR \fB\-\-url\fR url [\-\-is who]
.IP
ldap2csv.pl \fBprobe\fR \fB\-\-source\fR ldif [\-\-is who]
.IP
ldap2csv.pl \fBschema\fR \fB\-\-url\fR url [\-\-output ldif]
.IP
ldap2csv.pl \fBschema\fR \fB\-\-source\fR ldif [\-\-output ldif]
.IP
ldap2csv.pl \fBcollect\fR \fB\-\-url\fR url [\-\-sql|\-\-csv|\-\-ldif] [\-\-output file] \fB\-\-is\fR who [[--relation attribute] ...]
.IP
ldap2csv.pl \fBtree2csv\fR \fB\-\-csv \-\-init\fR initset \-\-reliation recursion_setting \-\-reliation relation [\-\-output file] [\-\-separator !]
.IP
ldap2csv.pl \fBtree2csv\fR \fB\-\-sql \-\-init\fR initset \-\-reliation recursion_setting \-\-reliation relation [\-\-output file] [\-\-separator !]
.SH AUTHOR
Written by Xibo Ning.
.SH "REPORTING BUGS"
Report ldap2csv.pl bugs to anzhou94@gmail.com.
.SH COPYRIGHT
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
.br
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
