#!/bin/sh
eval 'perl --version >/dev/null 2>&1 || { echo "No Perl interpreter found";exit 1; }';
#! -*-perl-*-
eval 'exec perl -x -wS $0 ${1+"$@"}'
  if 0;

use warnings;
use strict;
use feature qw(say);
use English qw( -no_match_vars );

my $nerd_name  = q{xning};
my $nerd_email = q{anzhou94@gmail.com};

sub main;
sub usage;
sub AUTOLOAD;
sub is_text_file;
sub verbose;
sub init_options;
sub select_operation_mode;
sub process_options;
sub audit_options;
sub import_mod_needed;
sub get_enabled_mode;
sub get_base_dn;
sub get_schema_from_net;
sub get_schema_from_ldif;
sub get_all_objectclasses;
sub get_objectclasses_details_by_names;
sub get_ldap_from_net;
sub dispatch_actions;
sub probe;
sub schema;
sub collect;
sub tree2csv;

sub construct_objectclasses_tree;
sub get_objectclasses_attrs;
sub enable_ssl_for_ldap;

#####################################################################
# If we import some modules at runtime, we have a chance to do more.#
# Just as you see, it's some complicated.                           #
#####################################################################
BEGIN {
    my $version = q{0.1.3};

    # When in production environment, we should disable this env var. So we
    # will use our version croak func that does not give stack infos.
    $ENV{LDAP2CSV_DEVEL} = 0 if ( not exists $ENV{LDAP2CSV_DEVEL} );

    # Here, if a module, we assign it a hash, has 'import' key, we will eval
    # the value of the 'import' key to import the module. While, if a module
    # has 'check' key, we will run the value of the 'check' key as additional
    # checks for the module.
    # Others modules, we just simply import them as usual.
    my $simple_mods = [
        q{Getopt::Long},    q{File::Basename},    q{Data::Dumper},          q{Data::Dump},
        q{Net::LDAP},       q{Net::LDAP::Filter}, q{Net::LDAP::LDIF},       q{Net::LDAP::Schema},
        q{Net::LDAP::Util}, q{Net::LDAP::DSML},   q{File::MimeInfo::Magic}, q{Net::DNS},
        q{Term::ANSIColor}, q{Term::ReadKey},     q{Text::Wrap},            q{Text::CSV_XS},
    ];

    push @{$simple_mods}, q{Carp} if ( exists $ENV{LDAP2CSV_DEVEL} and $ENV{LDAP2CSV_DEVEL} );

    eval join q{ }, q{sub croak}, ( join qq{\n}, q[{], q{verbose @_;}, q{exit 1;}, q[}] )
      if ( not exists $ENV{LDAP2CSV_DEVEL} or !$ENV{LDAP2CSV_DEVEL} );

    my $mod_need = {
        q{version} => {
            q{import} => 'use version; our $VERSION = qv(q{' . $version . '})',
        },
        q{DBI} => {
            q{check} => sub {
                my $mod_need = shift;
                my $dbi_drv  = q[SQLite];
                return scalar( grep { $_ eq $dbi_drv } DBI->available_drivers ) % 2;
            },
            q{require} => [ q{DBD::SQLite}, ],
        },
        q{File::Temp} => { q{import} => 'use File::Temp qw(tempfile)', },
        q{Data::Dump} => { q{import} => 'use Data::Dump qw(dump)', },
    };

    map { $mod_need->{qq[$_]} = {}; }
      grep { not exists $mod_need->{qq[$_]}; } @{$simple_mods};

    if ( grep { $_ eq q{list-packages} } @ARGV ) {
        say join qq{\n}, q{Need following Perl modules:}, map { q[ ] x 4 . $_ } (
            keys %{$mod_need},
            map { @{ $mod_need->{qq[$_]}->{require} } }
              grep { exists $mod_need->{qq[$_]}->{require} and @{ $mod_need->{qq[$_]}->{require} } }
              keys %{$mod_need}
        );
        exit;
    }

    # Check modules asap so we could know that we should quit with a warning or
    # try our best to do something that we can do.
    # If want to use moduels availabe infos, the following hash, $mod_need, could be used.
    # We will export this hash by function mod_available_status.
    map {
        my $mod = $_;
        exists $mod_need->{qq[$mod]}->{import} ? eval qq[$mod_need->{qq[$mod]}->{import}] : eval qq{use $mod};
        if ($@) {
            $mod_need->{qq[$mod]}->{available} = 0;
        }
        else {
            $mod_need->{qq[$mod]}->{available} =
              exists $mod_need->{qq[$mod]}->{check} ? &{ $mod_need->{qq[$mod]}->{check} } : 1;
        }
    } ( keys %{$mod_need} );

    # def is_mod_*_available functions
    map {
        my $mod                = $_;
        my $mod_name_canonical = lc($mod);
        $mod_name_canonical =~ y/:/_/s;
        my $sub_name = join q{_}, q{is_mod}, $mod_name_canonical, q{available};
        eval join q[ ], qq[sub], $sub_name,
          ( join qq[\n], q[{], q[ ] x 4 . q[return] . q[ ] . $mod_need->{qq[$mod]}->{available} . q[;], q[}] );
    } ( keys %{$mod_need} );

    my $mod_status = [];
    map {
        my ( $mod_str, $mod_available_str, $mod_import_str ) = qw();
        $mod_available_str = join q{ => }, q[q{available}], $mod_need->{qq[$_]}->{available};
        if ( exists $mod_need->{qq[$_]}->{import} ) {
            $mod_import_str = join q{ => }, q[q{import}], q[q{] . $mod_need->{qq[$_]}->{import} . q[}];
            $mod_str = join qq{,\n}, ( $mod_available_str, $mod_import_str );
        }
        else {
            $mod_str = $mod_available_str;
        }
        $mod_str = join q{ => }, q[q{] . qq[$_] . q[}], ( join q{ }, q[{], $mod_str, q[}] );
        push @{$mod_status}, $mod_str;
    } ( keys %{$mod_need} );

    # def mod_available_status function
    my $mod_status_str = join q{, }, @{$mod_status};
    eval join q{ }, q{sub}, q{mod_available_status},
      ( join qq{\n}, q[{], ( join q{ }, q{return}, ( join qq{\n}, q[{], $mod_status_str, q[}] ), q{;} ), q[}] );

    # OK, give users some tips about which module he/she need install and how to install these modules.
    {
        no strict 'subs';
        no strict 'refs';
        my @mod_unavailable = grep {
            my $mod_name_canonical = lc($_);
            $mod_name_canonical =~ y/:/_/s;
            &{"is_mod_${mod_name_canonical}_available"} ? 0 : 1;
        } keys %{$mod_need};

        if ( scalar(@mod_unavailable) != 0 ) {
            print STDERR q{The following modules are not available:} . qq{\n};
            print STDERR q{ } x 4
              . $_
              . qq{\n} foreach (
                sort @mod_unavailable,
                map { @{ $mod_need->{qq[$_]}->{require} } }
                grep { exists $mod_need->{qq[$_]}->{require} and @{ $mod_need->{qq[$_]}->{require} } } @mod_unavailable
              );
            print STDERR qq{\n\n};
            print STDERR q{Pls use your system package management tool to install them. F.g.,} . qq{\n};
            print STDERR q{if you system is RHEL-like, you can use yum(8).} . qq{\n};
            print q{And perhaps, you need configure EPEL repo.} . qq{\n};
            print STDERR q{For EPEL, pls reference https://fedoraproject.org/wiki/EPEL.} . qq{\n};
            print STDERR q{Or you can try cpan command: https://metacpan.org/pod/CPAN.} . qq{\n};
            print STDERR qq{\n};
            print STDERR (
                join q{ },
                q{yum install},
                ( map { join q{}, q{'}, q{perl}, q{(}, $_, q{)}, q{'} } sort @mod_unavailable ),
                (
                    map { join q{}, q{'}, q{perl}, q{(}, $_, q{)}, q{'} }
                      map { @{ $mod_need->{qq[$_]}->{require} } }
                      grep { exists $mod_need->{qq[$_]}->{require} and @{ $mod_need->{qq[$_]}->{require} } }
                      @mod_unavailable
                ),
            ) . qq{\n};
            exit(1);
        }
    }
}

######################################################################################
# While to check some module available or not, you should use this $mod_need hash,   #
# instead of the is_mod_.*_available function. Or you need be more careful when      #
# 'use strict'. You need proper disable it locally.                                  #
######################################################################################

my $mod_need;
our $VERSION;
{
    no strict 'subs';
    $mod_need = mod_available_status;
}

import_mod_needed($mod_need);

# From here, all modules are imported. Some vars need also be imported.
{
    no strict 'vars';
    $VERSION = $VERSION;
}

use utf8;
use open IO => q[:utf8];

binmode STDOUT, q[:utf8];
binmode STDIN,  q[:utf8];
binmode STDERR, q[:utf8];

###################################################################################
# Now we only check the options that accept a simple value as their parameters,   #
# f.g., string, integer, and boolean, reference, etc.                             #
# I don't plan to support any more types.                                         #
# We will run pre audit func before auditing options, and run post audit func     #
# after auditing options. So, if need set default values, it's better to use the  #
# pre audit func, and to parse and verify options' values, post audit is a better #
# choice.                                                                         #
###################################################################################
my $default = {
    q{shared} => {
        q{options checking} => {
            q{just one and only one} => {
                q{output format} => [ q{sql},     q{csv},      q{ldif}, ],
                q{mode}          => [ q{collect}, q{tree2csv}, q{probe}, q{schema}, ],
            },
            q{associate} => { q{csv} => [ q{separator}, ], },
        },

        q{DBI}  => { q{driver} => q{SQLite}, q{max table name length} => 128, },
        q{LDAP} => {
            q{schema} => q{},
            q{addr}   => q{},
            q{port}   => 389,
            q{ssl}    => {
                q{verify} => 0,
                q{cafile} => q{},
            },
        },
        q{default} => {},
    },
    q{probe} =>
      { q{options checking} => { q{just one and only one} => { q{input source} => [ q{source}, q{url} ], }, }, },
    q{schema} => {
        q{options checking} => {
            q{associate}             => { q{schema}       => [ q{ldif}, ], },
            q{just one and only one} => { q{input source} => [ q{source}, q{url} ], },
        },
    },
    q{collect} => {
        q{options checking} => {
            q{associate}             => { q{collect}      => [q{url}], },
            q{just one and only one} => { q{filter types} => [ q{is}, q{maybe} ] },
        },
        q{default} => {},
    },
    q{tree2csv} => {

        q{options checking} => {
            q{neccessary} => [ q{relation}, q{init}, q{source}, ],
            q{just one and only one} => { q{output format} => [ q{csv}, q{sql} ], }
        },
        q{default} => {},
    },
    q{program} => {
        q{version} => $VERSION,
        q{name}    => basename($0),
    },
};

# Some functions in the follow hash is very long and so urgly, while they are really simple.
# If a work mode, f.g. tree2csv, support different input source formats, and support export
# differnet output formats, while all we need do is to read input, construct a entry,
# then do some calculation, at last export the output, we need consider several conditions.
# So I use goto statement here and there and do not care any complaints on that.
my $cmd = {
    q{options} => {

        q{schema} => {
            q{help} =>
q{Enalbe schema work mode, get LDAP schema from LDAP server or other data sources, then display the schema or output the schema to STDOUT or other files. Only support LDIF output format},
        },
        q{probe} => {
            q{help} =>
q{As your faithful servant, help you to find who, in LDAP terms, which object class, we can query and learn from LDAP server or other data sources. Only support LDIF output format.},
        },
        q{collect} => {
            q{help} =>
q{Enable collect work mode to collect some who's data, in LDAP terms, some objects' data, from LDAP server. This the default action},
        },
        q{tree2csv} => {
            q{help} =>
q{Enable tree2csv work mode to transfer a tree to csv so shell can easily do more. If need, this mode will do rescursion.},
            q{pre audit} => sub {
                my ( $cmd, $default ) = @_;

                my ($mode) = grep { $cmd->{operation}->{mode}->{qq[$_]}->{value}; } keys %{ $cmd->{operation}->{mode} };
                return if ( $mode ne q{tree2csv} );
                croak q{The work mode need the --source option.}
                  if ( !$cmd->{operation}->{qq[$mode]}->{source}->{value} );

                my ( $source, $init );
                $source = $cmd->{operation}->{qq[$mode]}->{source}->{value};
                $default->{tree2csv}->{init} = {} if ( not exists $default->{tree2csv}->{init} );
                $init = $default->{tree2csv}->{init};

                # To create init rules and sets for doing recursions.
                {

                    map { $init->{set}->{origin}->{qq[$_]} = 1; } @{ $cmd->{operation}->{qq[$mode]}->{init}->{value} };

                    map {
                        my ( $init_attr, $init_attr_after_transfer, $rec_attr, $rec_attr_after_transfer ) = split q[:];
                        if ( not exists $init->{q[transfer rule]} ) {
                            croak q{You should give at least the initial set and the recursion attribute.}
                              if ( not( defined($init_attr) and $init_attr and defined($rec_attr) and $rec_attr ) );
                            $init->{q[transfer rule]} = [];
                            if ( defined($init_attr_after_transfer) and $init_attr_after_transfer ) {
                                push @{ $init->{q[transfer rule]} }, { qq[$init_attr] => $init_attr_after_transfer };
                            }
                            else {
                                push @{ $init->{q[transfer rule]} }, { qq[$init_attr] => $init_attr };
                            }
                            if ( defined($rec_attr_after_transfer) and $rec_attr_after_transfer ) {
                                push @{ $init->{q[transfer rule]} }, { qq[$rec_attr] => $rec_attr_after_transfer };
                            }
                            else {
                                push @{ $init->{q[transfer rule]} }, { qq[$rec_attr] => $rec_attr };
                            }
                            $init->{q[recursion attr]} = $rec_attr;
                        }
                        else {
                            croak join qq{\n}, q{More than one recursion relation found:},
                              ( grep { m!^[^:]+:[^:]+:[^:]+(?:[^:]+)*!; }
                                  @{ $cmd->{operation}->{qq[$mode]}->{init}->{value} } );
                        }
                      }
                      grep { m!^[^:]+:[^:]+:[^:]+(?:[^:]+)*!; }
                      @{ $cmd->{operation}->{qq[$mode]}->{relation}->{value} };

                    map { $init->{q[attr that we care]}->{qq[$_]} = 1; }
                      grep { not m!^[^:]+:[^:]+:[^:]+(?:[^:]+)*!; }
                      @{ $cmd->{operation}->{qq[$mode]}->{relation}->{value} };

                }

                # We need know what the source is, sql, ldif, or csv. Now we only have a comeplicated and urgly
                # solution. You cnanot believe that File::MimeInfo::Magic will use the suffixes of files checked.
                # Eh, the is_text_file is not good enough for our perpose.
                if ( is_text_file $source ) {
                    open my $h, q[<], $source or croak q{Failed to open source file } . $source;
                    my ( $first_line, @attrs_from_source );
                    while (<$h>) {
                        chomp;
                        next if ( m!^$! or m!^#! );
                        $first_line = $_;
                        last;
                    }
                    close $h;

                    @attrs_from_source = split $cmd->{operation}->{qq[$mode]}->{separator}->{value}, $first_line;

                    if ( not @attrs_from_source or scalar(@attrs_from_source) <= 1 ) {
                        $default->{tree2csv}->{init}->{q[source type]} = q{ldif};
                    }
                    else {
                        my %attr_from_source_hash;
                        map { $attr_from_source_hash{qq[$_]} = 1; } @attrs_from_source;

                        my @result =
                          grep { not exists $attr_from_source_hash{qq[$_]}; }

                          map {
                            my $hash_ref = $_;
                            map { $_ => $hash_ref->{qq[$_]}; } keys %{$hash_ref};
                          } @{ $default->{tree2csv}->{init}->{q[transfer rule]} };

                        if ( scalar(@result) > 0 ) {
                            $default->{tree2csv}->{init}->{q[source type]} = q{ldif};
                        }
                        else {
                            $default->{tree2csv}->{init}->{q[source type]} = q{csv};
                        }
                    }
                }
                else {
                    if ( ( mimetype($source) ) eq q{text/x-ldif} ) {
                        $default->{tree2csv}->{init}->{q[source type]} = q{ldif};
                    }
                    else {
                        $default->{tree2csv}->{init}->{q[source type]} = q{sql};
                    }
                }

                if ( $default->{tree2csv}->{init}->{q[source type]} eq q{sql} ) {
                    $default->{shared}->{DBI}->{database} = $cmd->{operation}->{qq[$mode]}->{source}->{value};
                    my ( $tbl, $sqlite, $dbh, $sth, $db, @row, $sql );
                    {
                        $db     = $source;
                        $sqlite = join q{:}, q{dbi}, $default->{shared}->{DBI}->{driver}, ( join q{=}, q{dbname}, $db );
                        $dbh    = DBI->connect( $sqlite, q{}, q{}, { RaiseError => 1, AutoCommit => 1 } );
                        $sth    = $dbh->table_info( undef, q{main}, undef, q{table} );
                        $tbl    = $sth->fetchall_arrayref->[0]->[2];
                        $sth->finish;
                    }

                    croak q{Failed to get the table name, pls check.} if ( not defined($tbl) or !$tbl );
                    $default->{shared}->{DBI}->{q[table name]} = $tbl;

                    # To transfer the init set to the "middle type" so the recursions could be done.
                    # We only expect that there is one and only one key and value in the following hash ref.
                    $sql = join q{ }, q{SELECT},
                      ( join q{, }, values %{ $default->{tree2csv}->{init}->{q[transfer rule]}->[0] } ), q{FROM},
                      $default->{shared}->{DBI}->{q[table name]}, q{WHERE},
                      ( join q{, }, keys %{ $default->{tree2csv}->{init}->{q[transfer rule]}->[0] } ), q{IN (},
                      ( join q{, }, map { qq['$_'] } keys %{ $default->{tree2csv}->{init}->{set}->{origin} } ),
                      q{)};
                    $sth = $dbh->prepare($sql) or croak q{Failed to prepare the SQL: } . $sql;
                    $sth->execute;
                    map {
                        map {
                            croak q{We do not support the reference types in the init set.}
                              if ( ref $_ ne q{} );
                            $default->{tree2csv}->{init}->{set}->{now} = {}
                              if ( not exists $default->{tree2csv}->{init}->{set}->{now} );
                            $default->{tree2csv}->{init}->{set}->{now}->{qq[$_]} = 1;
                          } @{$_}
                    } @{ $sth->fetchall_arrayref };

                    $dbh->disconnect;
                }
                elsif ( $default->{tree2csv}->{init}->{q[source type]} eq q{ldif} ) {
                    my ( $ldif, $entry, $lined_values );
                    my $attr = [
                        map {
                            my $hash_ref = $_;
                            map { $_ => $hash_ref->{qq[$_]} } keys %{$hash_ref}
                        } @{ $default->{qq[$mode]}->{init}->{q[transfer rule]} }
                    ];

                    $ldif =
                      Net::LDAP::LDIF->new( $cmd->{operation}->{qq[$mode]}->{source}->{value}, "r", onerror => 'undef' )
                      or croak q{Failed to create a Net::LDAP::LDIF object.};

                    croak q{Failed to get a LDIF handler.} if ( not defined($ldif) );

                    while ( not $ldif->eof() ) {
                        my $lined_value = [];
                        $entry = $ldif->read_entry();
                        if ( $ldif->error() ) {
                            verbose "Error msg:\n", $ldif->error(), qq{\n}, "Error lines:\n", $ldif->error_lines();
                        }
                        else {
                            map {
                                my $val = $entry->get_value($_);
                                croak join q{ }, q{The}, $mode,
                                  q{work mode only support simple recursion on lined data.}
                                  if ( ref $val ne q{} );
                                push @{$lined_value}, $val;
                            } @{$attr};

                            my ( $init_attr, $init_attr_after_transfer, $rec_attr, $rec_attr_after_transfer ) =
                              @{$lined_value};
                            if ( exists $default->{tree2csv}->{init}->{set}->{origin}->{qq[$init_attr]} ) {
                                $default->{tree2csv}->{init}->{set}->{now}->{qq[$init_attr_after_transfer]} = 1;
                            }
                        }
                    }
                    $ldif->done();
                }
                elsif ( $default->{tree2csv}->{init}->{q[source type]} eq q{csv} ) {

                    my $skip_the_first_line = 1;
                    my $attr_from_cmd_line;
                    my ( $csv, $h, $row, $attr, $val );
                    $attr = {};

                    push @{$attr_from_cmd_line}, map {
                        my $hash_ref = $_;
                        map { $_ => $hash_ref->{qq[$_]}; } keys %{$hash_ref};
                    } @{ $default->{tree2csv}->{init}->{q[transfer rule]} };
                    push @{$attr_from_cmd_line}, keys %{ $default->{tree2csv}->{init}->{q[attr that we care]} };

                    $csv = Text::CSV_XS->new(
                        {
                            sep_char    => $cmd->{operation}->{qq[$mode]}->{separator}->{value},
                            binary      => 1,
                            quote_char  => q{'},
                            escape_char => q{\\},
                        }
                    ) or croak q{Failed to create Text::CSV_XS object.};
                    open $h, q{<}, $cmd->{operation}->{qq[$mode]}->{source}->{value}
                      or croak q{Failed to open file } . $cmd->{operation}->{qq[$mode]}->{source}->{value};

                    while ( $row = $csv->getline($h) ) {
                        if ($skip_the_first_line) {
                            $skip_the_first_line = 0;
                            my $i = 0;
                            map { $attr->{qq[$_]} = $i if ( not exists $attr->{qq[$_]} ); $i++; } @{$row};
                            next;
                        }

                        my $lined_value = [ map { $row->[ $attr->{qq[$_]} ]; } @{$attr_from_cmd_line} ];

                        my ( $init_attr, $init_attr_after_transfer, $rec_attr, $rec_attr_after_transfer ) =
                          @{$lined_value};
                        if ( exists $default->{tree2csv}->{init}->{set}->{origin}->{qq[$init_attr]} ) {
                            $default->{tree2csv}->{init}->{set}->{now}->{qq[$init_attr_after_transfer]} = 1;
                        }

                    }

                    close $h;

                }
                else {
                    croak q{Unkonw source file type. Is it a csv, ldif, or a SQLite3 database?};
                }

            },
            q{post audit} => sub {
                my ( $cmd, $default ) = @_;

                my ($mode) = grep { $cmd->{operation}->{mode}->{qq[$_]}->{value}; } keys %{ $cmd->{operation}->{mode} };
                croak q{Failed to parse url because of no enabled mode found.} if ( !$mode );
                croak q{The work mode } . $mode . q{ requires more than one relation.}
                  if ( $mode eq q{tree2csv}
                    and scalar( @{ $cmd->{operation}->{qq[$mode]}->{relation}->{value} } ) <= 1 );
            },
        },
        q{verbose} => { q{help} => q{Output verbosely. No effect now.}, },
        q{verify}  => { q{help} => q{Whether verify LDAP server SSL certificate. Default is not to.}, },
        q{cafile}  => {
            q{help} =>
q{Set the path of the CA certificate. You need this if you want to verify the server certificate, the mean while, the LDAP server uses a self-signed certificate.},
            q{type} => q{s},
        },
        q{sql} => {
            q{help} =>
q{Ouput SQL statements that you can use to create a SQLite3 database. If give a output file, will create a SQLite database for you.},
        },
        q{csv} => {
            q{help}      => q{Output csv. You can set separator as need.},
            q{pre audit} => sub {
                my ( $cmd, $default ) = @_;
                my $mode = get_enabled_mode( $cmd, $default );
                $cmd->{operation}->{qq[$mode]}->{separator}->{value} = q{!}
                  if ( !$cmd->{operation}->{qq[$mode]}->{separator}->{value} );
            },
        },
        q{ldif} => {
            q{help}      => q{Output LDIF, LDAP Data Interchange Format, which is text and we can easily read in.},
            q{pre audit} => sub {
                my ( $cmd, $default ) = @_;
                my $modes_to_enable_this = [ q{schema}, ];
                my $output = [ q{sql}, q{csv}, q{ldif}, ];
                my ($mode) = grep { $cmd->{operation}->{mode}->{qq[$_]}->{value}; } keys %{ $cmd->{operation}->{mode} };
                croak q{Failed to parse url because of no enabled mode found.} if ( !$mode );
                my @find_mode_to_enable_this = grep { $mode eq $_ } @{$modes_to_enable_this};

                # Enable LDIF output format for some mode, f.g., schema.
                if ( scalar(@find_mode_to_enable_this) ) {
                    map { $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{value} = 0; } @{$output};
                    $cmd->{operation}->{qq[$mode]}->{ldif}->{value} = 1;
                }

                # Set LDIF output format as the default format if none of output formats is enabled.
                my @enabled_output_formats =
                  grep { $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{value} }
                  grep { exists $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{value} } @{$output};
                $cmd->{operation}->{qq[$mode]}->{ldif}->{value} = 1 if ( scalar(@enabled_output_formats) == 0 );
            },
        },
        q{output} => {
            q{type} => q{s},
            q{help} => q{Output to a named file instead of to the stdout.},
        },
        q{separator} => {
            q{type} => q{s},
            q{help} => q{Set the separator when output csv format.},
        },
        q{help} => {
            q{help}  => q{Display this help page.},
            q{value} => 0,
        },
        q{source} => {
            q{type} => q{s},
            q{help} =>
q{Set a file as data source. The file may be SQLite3 table, csv, or LDIF file. Not all work modes support this option.},
        },
        q{version} => {
            q{help}     => q{Show the program version, then quit.},
            q{value}    => 0,
            q{callback} => sub {
                my ( $cmd, $default ) = @_;
                say $VERSION;
                exit;
            },
        },
        q{is} => {
            q{help}  => q{It is who we will probe, or whose data we will collect.},
            q{value} => [],
            q{type}  => q{s},
        },
        q{maybe} => {
            q{help}  => q{It may be who we will probe, or whose data we will collect.},
            q{value} => [],
            q{type}  => q{s},
        },
        q{url} => {
            q{type} => q{s},
            q{help} =>
q{Set LDAP url: schema://server:port, where schema could be one of ldap, ldaps, and ldapi. DO NOT think too much, we only support "ldap" and "ldaps" now. And we DO NOT completely support URLs as the ldapurl(1) does. Perhaps we will support that in the future, while probably we will never do that.},
            q{post audit} => sub {
                my ( $cmd, $default ) = @_;
                my ( $schema, $port, $addr ) = qw(ldap 389);
                my $lc_schema;

                my ($mode) = grep { $cmd->{operation}->{mode}->{qq[$_]}->{value}; } keys %{ $cmd->{operation}->{mode} };
                croak q{Failed to parse url because of no enabled mode found.} if ( !$mode );

                my $url = $cmd->{operation}->{qq[$mode]}->{url}->{value};
                return if ( !$url );

                if ( $url =~ m!^((?<schema>[^:]+)://)* (?<addr>[^:]+):* ((?<port>\d{1,5}))*!imx ) {
                    $schema = $+{schema} if ( exists $+{schema} );
                    $addr   = $+{addr}   if ( exists $+{addr} );
                    $port   = $+{port}   if ( exists $+{port} );
                }
                croak join q{ }, q{No LDAP server address found in url:}, $url
                  if ( ( not defined($addr) ) or $addr eq q{} );

                $lc_schema = lc $schema;
                my @available_schemas = grep { $lc_schema eq $_; } qw( ldap ldaps ldapi );
                croak join q{ }, $schema, q{is not available schema, please chose one from:},
                  ( join q{ }, qw( ldap ldaps ldapi ) )
                  if ( scalar(@available_schemas) != 1 );

                croak join q{ }, $port, q{is not available port} if ( not( $port > 0 ) and ( $port < 65535 ) );

                {
                    my $res   = Net::DNS::Resolver->new;
                    my $query = $res->search($addr);
                    croak join q{ }, q{Can not resolve server name}, qq["$addr"] if ( !$query );
                }

                $default->{shared}->{LDAP}->{schema} = $schema;
                $default->{shared}->{LDAP}->{addr}   = $addr;
                $default->{shared}->{LDAP}->{port}   = $port;
                $default->{shared}->{LDAP}->{ssl}->{enable} = 1 if ( $schema eq q{ldaps} or lc($schema) eq q{ldaps} );
            },
        },
        q{init} => {
            q{type}  => q{s},
            q{value} => [],
            q{help} =>
q {In tree2csv work mode, initialize the set from which we will add more if some data items follow the relations set by the --relation option.},
        },
        q{relation} => {
            q{type}  => q{s},
            q{value} => [],
            q{help} =>
q{Set relations for tree2csv work mode, or set attributes for collect work when output format is sql or csv.},
        },
    },

    q{operation} => {
        q{mode} => {

            # Here options settings will copy to chosen mode after processing options.
            q{options} => [ q{schema}, q{probe}, q{collect}, q{tree2csv}, ],
        },

        q{shared} => {
            q{options} => [
                q{verbose}, q{sql},    q{csv},     q{ldif},   q{output}, q{separator},
                q{help},    q{source}, q{version}, q{verify}, q{cafile},
            ],
        },

        q{schema} => { q{options} => [ q{url}, ], },

        q{probe} => { q{options} => [ q{is}, q{url}, ], },

        q{collect}  => { q{options} => [ q{is},   q{url}, q{maybe}, q{relation}, ], },
        q{tree2csv} => { q{options} => [ q{init}, q{relation}, ], },
    },
    q{output} => {
        q{collect} => {
            q{ldif} => sub {
                my ( $cmd, $default ) = @_;
                my $mode = q{collect};
                my $search = get_ldap_from_net( $cmd, $default );

                if ( $cmd->{operation}->{qq[$mode]}->{ldif}->{value} ) {
                    if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} ) {
                        Net::LDAP::LDIF->new( $cmd->{operation}->{qq[$mode]}->{output}->{value}, "w" )
                          ->write( $search->entries );
                    }
                    else {
                        Net::LDAP::LDIF->new( \*STDOUT, "w" )->write( $search->entries );
                    }
                }

            },

            q{sql} => sub {
                my ( $cmd, $default ) = @_;
                my ( $mode, $search, $schema, $objectclasses );
                my ( $sqlite, $dbh, $db, $tbl, $create_tbl_stm, $drop_tbl_stm, $insert_tbl_stm,
                    $prefix_of_insert_tbl_stm );
                my ( $attr, $attr_from_argument );
                $mode = q{collect};
                $search = get_ldap_from_net( $cmd, $default );

                $schema = get_schema_from_net( $cmd, $default );

                my $csv_output;

                if ( scalar( @{ $cmd->{operation}->{qq[$mode]}->{is}->{value} } ) > 0 ) {
                    $objectclasses =
                      get_objectclasses_details_by_names( $schema, $cmd->{operation}->{qq[$mode]}->{is}->{value} );
                }
                elsif ( scalar( @{ $cmd->{operation}->{qq[$mode]}->{maybe}->{value} } ) > 0 ) {
                    $objectclasses =
                      get_objectclasses_details_by_names( $schema, $cmd->{operation}->{qq[$mode]}->{maybe}->{value} );
                }

                $attr = get_objectclasses_attrs($objectclasses);

                if ( scalar( @{ $cmd->{operation}->{qq[$mode]}->{relation}->{value} } ) > 0 ) {
                    $attr_from_argument = {};
                    map { $attr_from_argument->{qq[$_]} = 0; } @{ $cmd->{operation}->{qq[$mode]}->{relation}->{value} };

                    my @tmp_attrs =
                      grep { exists $attr_from_argument->{qq[$_]}; }
                      @{ $cmd->{operation}->{qq[$mode]}->{relation}->{value} };

                    $attr = \@tmp_attrs if ( scalar(@tmp_attrs) > 0 );
                }

                map { $_ =~ y/-/_/s; } @{$attr} if ( $cmd->{operation}->{qq[$mode]}->{sql}->{value} );

                if ( $cmd->{operation}->{qq[$mode]}->{sql}->{value} ) {

                    if ( scalar( @{ $cmd->{operation}->{qq[$mode]}->{is}->{value} } ) > 0 ) {
                        $tbl = join q{_}, @{ $cmd->{operation}->{qq[$mode]}->{is}->{value} };
                    }
                    elsif ( scalar( @{ $cmd->{operation}->{qq[$mode]}->{maybe}->{value} } ) > 0 ) {
                        $tbl = join q{_}, @{ $cmd->{operation}->{qq[$mode]}->{maybe}->{value} };
                    }

                    $tbl = substr( $tbl, 0, $default->{shared}->{DBI}->{qq[max table name length]} - 1 )
                      if ( length($tbl) > $default->{shared}->{DBI}->{qq[max table name length]} );
                    {
                        local $INPUT_RECORD_SEPARATOR = q{_};
                        chomp($tbl);
                    }

                    $create_tbl_stm = join q{ }, q{CREATE TABLE IF NOT EXISTS}, $tbl,
                      q{(}, ( join q{, }, map { $_ . q[ ] . q[TEXT] } @{$attr} ), q{)};
                    $drop_tbl_stm             = join q{ }, q{DROP TABLE IF EXISTS}, $tbl;
                    $prefix_of_insert_tbl_stm = join q{ }, q{INSERT INTO},          $tbl,
                      q[(], ( join q{, }, map { $_ } @{$attr} ), q[)], q{VALUES};

                    if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} ) {
                        $db = $cmd->{operation}->{qq[$mode]}->{output}->{value};
                    }
                    else {
                        $db = ( tempfile( UNLINK => 1, EXLOCK => 0 ) )[1];
                    }

                    $sqlite = join q{:}, q{dbi}, $default->{shared}->{DBI}->{driver}, ( join q{=}, q{dbname}, $db );
                    $dbh = DBI->connect( $sqlite, q{}, q{}, { RaiseError => 1, AutoCommit => 0 } );

                    if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} ) {
                        $dbh->do($_) foreach ( ( $drop_tbl_stm, $create_tbl_stm ) );
                        $dbh->commit;
                    }
                    else {
                        say q{BEGIN;};
                        say $drop_tbl_stm . q{;};
                        say $create_tbl_stm . q{;};
                        say q{COMMIT;};
                        say q{BEGIN;};
                    }
                }
                elsif ( $cmd->{operation}->{qq[$mode]}->{csv}->{value} ) {
                    if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} ) {
                        open $csv_output, q[>], $cmd->{operation}->{qq[$mode]}->{output}->{value}
                          or croak q{Failed to open file } . $cmd->{operation}->{qq[$mode]}->{output}->{value};
                        say $csv_output ( join $cmd->{operation}->{qq[$mode]}->{separator}->{value}, @{$attr} );
                        close $csv_output;
                        open $csv_output, q[>>], $cmd->{operation}->{qq[$mode]}->{output}->{value}
                          or croak q{Failed to open file } . $cmd->{operation}->{qq[$mode]}->{output}->{value};
                    }
                    else {
                        say join $cmd->{operation}->{qq[$mode]}->{separator}->{value}, @{$attr};
                    }
                }

                map {
                    my $values        = [];
                    my $general_entry = {};
                    my $entry         = $_;

                    # Structured data.
                    map {
                        my $entry_attr   = $_;
                        my @entry_values = qw();
                        @entry_values = $entry->get_value(qq[$entry_attr]);

                        if ( scalar(@entry_values) == 0 ) {
                            $general_entry->{qq[$entry_attr]} = {
                                q{value} => [ q{}, ],
                                q{count} => 1,
                            };
                        }
                        else {
                            $general_entry->{qq[$entry_attr]} = {
                                q{value} => \@entry_values,
                                q{count} => scalar(@entry_values),
                            };
                        }
                    } @{$attr};

                    # Advanced structured data.
                    foreach my $entry_attr ( @{$attr} ) {
                        if ( scalar( @{$values} ) == 0 ) {
                            map { push @{$values}, [ $_, ]; } @{ $general_entry->{$entry_attr}->{value} };
                        }
                        else {
                            my $new_array = [];
                            map {
                                my $val = $_;
                                map {
                                    my @new_val_array = ();
                                    push @new_val_array, @{$_}, $val;
                                    push @{$new_array}, \@new_val_array;
                                } @{$values};

                            } @{ $general_entry->{$entry_attr}->{value} };
                            $values = $new_array;
                        }

                    }

                    map {
                        if ( $cmd->{operation}->{qq[$mode]}->{sql}->{value} )
                        {
                            $insert_tbl_stm = join q{ }, $prefix_of_insert_tbl_stm, join q{ }, q[(],
                              ( join q{, }, map { $dbh->quote($_) } @{$_} ), q[)] . q{;};
                            if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} ) {
                                $dbh->do($insert_tbl_stm);
                            }
                            else {
                                say $insert_tbl_stm . q{;};
                            }
                        }
                        elsif ( $cmd->{operation}->{qq[$mode]}->{csv}->{value} ) {
                            if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} ) {
                                say $csv_output ( join $cmd->{operation}->{qq[$mode]}->{separator}->{value}, @{$_} );
                            }
                            else {
                                say join $cmd->{operation}->{qq[$mode]}->{separator}->{value}, @{$_};
                            }
                        }

                    } @{$values};

                } $search->entries;

                if ( $cmd->{operation}->{qq[$mode]}->{csv}->{value} ) {
                    close $csv_output if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} );
                }

                if ( $cmd->{operation}->{qq[$mode]}->{sql}->{value} ) {
                    if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} ) {
                        $dbh->commit;
                    }
                    else {
                        say q{COMMIT;};
                    }
                }
                $dbh->disconnect if ( $cmd->{operation}->{qq[$mode]}->{sql}->{value} );

            },
            q{csv} => sub {
                my ( $cmd, $default ) = @_;
                my $mode = get_enabled_mode( $cmd, $default );
                &{ $cmd->{output}->{qq[$mode]}->{sql} }( $cmd, $default );
            },
        },
        q{tree2csv} => {
            q{csv} => sub {
                my ( $cmd, $default ) = @_;
                my $mode = q{tree2csv};
                &{ $cmd->{output}->{qq[$mode]}->{sql} }( $cmd, $default );
            },
            q{ldif} => sub {
                my ( $cmd, $default ) = @_;
                my $mode = q{tree2csv};
                croak join q{ }, q{The}, $mode, q{work mode do not support output ldif format.};
            },
            q{sql} => sub {

                # We do not simply read all the data into memory because the data may be big.
                my ( $cmd, $default ) = @_;
                my $mode = q{tree2csv};
                my ( $origin_size, $at_last_size ) = qw(0 0);
                my ( $init_set, $result_set, $processed_init_set );

                $init_set           = $default->{tree2csv}->{init}->{set}->{now};
                $result_set         = [];
                $processed_init_set = {};

                if ( $default->{tree2csv}->{init}->{q[source type]} eq q{sql} ) {

                    my ( $tbl, $sqlite, $dbh, $sth, @row, $sql );

                    $sqlite = join q{:}, q{dbi}, $default->{shared}->{DBI}->{driver},
                      ( join q{=}, q{dbname}, $cmd->{operation}->{qq[$mode]}->{source}->{value} );
                    $dbh = DBI->connect( $sqlite, q{}, q{}, { RaiseError => 1, AutoCommit => 1 } );

                    $sql = join q{ }, q{SELECT}, (
                        join q{, },
                        (
                            map {
                                my $hash_ref = $_;
                                map { $_ => $hash_ref->{qq[$_]} } keys %{$hash_ref}
                            } @{ $default->{qq[$mode]}->{init}->{q[transfer rule]} }
                        ),
                        keys %{ $default->{qq[$mode]}->{init}->{q[attr that we care]} }
                      ),
                      q{FROM}, $default->{shared}->{DBI}->{q[table name]};

                    $sth = $dbh->prepare($sql);

                    # The init values should be added to the result set, do you think so?
                    $sth->execute;

                    while ( @row = $sth->fetchrow_array ) {
                        my ( $init_attr, $init_attr_after_transfer, $rec_attr, $rec_attr_after_transfer,
                            @remaider_values )
                          = @row;

                        next if ( !$rec_attr_after_transfer or !$init_attr_after_transfer );

                        if ( exists $init_set->{qq[$init_attr_after_transfer]} ) {
                            push @{$result_set}, \@remaider_values;
                        }
                    }

                  TREE2CSV_SQL_REDO:

                    $sth->execute;

                    $origin_size = scalar( keys %{$init_set} );

                    while ( @row = $sth->fetchrow_array ) {
                        my ( $init_attr, $init_attr_after_transfer, $rec_attr, $rec_attr_after_transfer,
                            @remaider_values )
                          = @row;

                        next if ( !$rec_attr_after_transfer or !$init_attr_after_transfer );

                        if ( exists $init_set->{qq[$rec_attr_after_transfer]}
                            and not exists $init_set->{qq[$init_attr_after_transfer]} )
                        {
                            $init_set->{qq[$init_attr_after_transfer]} = 1;
                            push @{$result_set}, \@remaider_values;
                        }
                    }

                    $at_last_size = scalar( keys %{$init_set} );

                    goto TREE2CSV_SQL_REDO if ( $at_last_size != $origin_size );

                    $dbh->disconnect;
                }
                elsif ( $default->{tree2csv}->{init}->{q[source type]} eq q{ldif} ) {
                    my ( $ldif, $entry, $lined_values );
                    my $attr = [
                        map { $_ } (
                            map {
                                my $hash_ref = $_;
                                map { $_ => $hash_ref->{qq[$_]} } keys %{$hash_ref}
                            } @{ $default->{qq[$mode]}->{init}->{q[transfer rule]} }
                        ),
                        keys %{ $default->{qq[$mode]}->{init}->{q[attr that we care]} }
                    ];

                    # OK. Add the init values to the result set.
                    $ldif =
                      Net::LDAP::LDIF->new( $cmd->{operation}->{qq[$mode]}->{source}->{value}, "r",
                        onerror => 'undef' );

                    while ( not $ldif->eof() ) {
                        $entry = $ldif->read_entry();
                        if ( $ldif->error() ) {
                            verbose "Error msg:\n", $ldif->error(), qq{\n}, "Error lines:\n", $ldif->error_lines();
                        }
                        else {

                            my $lined_value = [];
                            map {
                                my $val = $entry->get_value($_);
                                croak join q{ }, q{The}, $mode,
                                  q{work mode only support simple recursion on lined data.}
                                  if ( ref $val ne q{} );
                                push @{$lined_value}, $val;
                            } @{$attr};

                            my ( $init_attr, $init_attr_after_transfer, $rec_attr, $rec_attr_after_transfer,
                                @remaider_values )
                              = @{$lined_value};

                            next if ( !$init_attr_after_transfer );

                            if ( exists $init_set->{qq[$init_attr_after_transfer]} ) {
                                push @{$result_set}, \@remaider_values;
                            }
                        }
                    }

                    $ldif->done();

                  TREE2CSV_LDIF_REDO:

                    $ldif =
                      Net::LDAP::LDIF->new( $cmd->{operation}->{qq[$mode]}->{source}->{value}, "r",
                        onerror => 'undef' );

                    $origin_size = scalar( keys %{$init_set} );

                    while ( not $ldif->eof() ) {
                        $entry = $ldif->read_entry();
                        if ( $ldif->error() ) {
                            verbose "Error msg:\n", $ldif->error(), qq{\n}, "Error lines:\n", $ldif->error_lines();
                        }
                        else {
                            my $lined_value = [];
                            map {
                                my $val = $entry->get_value($_);
                                croak join q{ }, q{The}, $mode,
                                  q{work mode only support simple recursion on lined data.}
                                  if ( ref $val ne q{} );
                                push @{$lined_value}, $val;
                            } @{$attr};

                            my ( $init_attr, $init_attr_after_transfer, $rec_attr, $rec_attr_after_transfer,
                                @remaider_values )
                              = @{$lined_value};

                            next if ( !$rec_attr_after_transfer or !$init_attr_after_transfer );

                            if ( exists $init_set->{qq[$rec_attr_after_transfer]}
                                and not exists $init_set->{qq[$init_attr_after_transfer]} )
                            {
                                $init_set->{qq[$init_attr_after_transfer]} = 1;
                                push @{$result_set}, \@remaider_values;
                            }

                        }
                    }
                    $ldif->done();

                    $at_last_size = scalar( keys %{$init_set} );
                    goto TREE2CSV_LDIF_REDO if ( $origin_size != $at_last_size );
                }
                elsif ( $default->{tree2csv}->{init}->{q[source type]} eq q{csv} ) {
                    my $attr_from_cmd_line  = [];
                    my $skip_the_first_line = 1;
                    my ( $csv, $h, $row, $attr, $val );
                    $attr = {};

                    push @{$attr_from_cmd_line}, map {
                        my $hash_ref = $_;
                        map { $_ => $hash_ref->{qq[$_]}; } keys %{$hash_ref};
                    } @{ $default->{tree2csv}->{init}->{q[transfer rule]} };
                    push @{$attr_from_cmd_line}, keys %{ $default->{tree2csv}->{init}->{q[attr that we care]} };

                    {
                        # Add the init set to the result set.
                        $csv = Text::CSV_XS->new(
                            {
                                sep_char    => $cmd->{operation}->{qq[$mode]}->{separator}->{value},
                                binary      => 1,
                                quote_char  => q{'},
                                escape_char => q{\\},
                            }
                        ) or croak q{Failed to create Text::CSV_XS object.};
                        open $h, q{<}, $cmd->{operation}->{qq[$mode]}->{source}->{value}
                          or croak q{Failed to open file } . $cmd->{operation}->{qq[$mode]}->{source}->{value};

                        while ( $row = $csv->getline($h) ) {
                            if ($skip_the_first_line) {
                                $skip_the_first_line = 0;
                                my $i = 0;
                                map { $attr->{qq[$_]} = $i if ( not exists $attr->{qq[$_]} ); $i++; } @{$row};
                                next;
                            }

                            my $lined_value = [ map { $row->[ $attr->{qq[$_]} ]; } @{$attr_from_cmd_line} ];

                            my ( $init_attr, $init_attr_after_transfer, $rec_attr, $rec_attr_after_transfer,
                                @remaider_values )
                              = @{$lined_value};

                            next if ( !$init_attr_after_transfer );

                            if ( exists $init_set->{qq[$init_attr_after_transfer]} ) {
                                push @{$result_set}, \@remaider_values;
                            }

                        }

                        close $h;
                    }

                  TREE2CSV_CSV_REDO:

                    $csv = Text::CSV_XS->new(
                        {
                            sep_char    => $cmd->{operation}->{qq[$mode]}->{separator}->{value},
                            binary      => 1,
                            quote_char  => q{'},
                            escape_char => q{\\},
                        }
                    ) or croak q{Failed to create Text::CSV_XS object.};
                    open $h, q{<}, $cmd->{operation}->{qq[$mode]}->{source}->{value}
                      or croak q{Failed to open file } . $cmd->{operation}->{qq[$mode]}->{source}->{value};

                    $origin_size = scalar( keys %{$init_set} );

                    while ( $row = $csv->getline($h) ) {
                        if ($skip_the_first_line) {
                            $skip_the_first_line = 0;
                            my $i = 0;
                            map { $attr->{qq[$_]} = $i if ( not exists $attr->{qq[$_]} ); $i++; } @{$row};
                            next;
                        }

                        my $lined_value = [ map { $row->[ $attr->{qq[$_]} ]; } @{$attr_from_cmd_line} ];

                        my ( $init_attr, $init_attr_after_transfer, $rec_attr, $rec_attr_after_transfer,
                            @remaider_values )
                          = @{$lined_value};

                        next if ( !$rec_attr_after_transfer or !$init_attr_after_transfer );

                        if ( exists $init_set->{qq[$rec_attr_after_transfer]}
                            and not exists $init_set->{qq[$init_attr_after_transfer]} )
                        {
                            $init_set->{qq[$init_attr_after_transfer]} = 1;
                            push @{$result_set}, \@remaider_values;
                        }

                    }

                    close $h;

                    $at_last_size = scalar( keys %{$init_set} );
                    goto TREE2CSV_CSV_REDO if ( $origin_size != $at_last_size );
                }
                else {
                    croak q{Unknown source file type.};
                }

                if ( $cmd->{operation}->{qq[$mode]}->{csv}->{value} ) {
                    if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} ) {
                        open my $h, q{>}, $cmd->{operation}->{qq[$mode]}->{output}->{value}
                          or croak q{Failed to open file } . $cmd->{operation}->{qq[$mode]}->{output}->{value} . q{.};
                        map {
                            say $h ( join $cmd->{operation}->{qq[$mode]}->{separator}->{value}, map { $_ } @{$_} );
                        } @{$result_set};
                        close $h;
                    }
                    else {
                        map {
                            say join $cmd->{operation}->{qq[$mode]}->{separator}->{value}, map { $_ } @{$_};
                        } @{$result_set};
                    }

                }
                elsif ( $cmd->{operation}->{qq[$mode]}->{sql}->{value} ) {

                    my ( $sqlite, $dbh, $db, $tbl, $create_tbl_stm, $drop_tbl_stm, $insert_tbl_stm,
                        $prefix_of_insert_tbl_stm );

                    $tbl = join q{_}, keys %{ $default->{tree2csv}->{init}->{q[attr that we care]} };
                    $tbl = substr( $tbl, 0, $default->{shared}->{DBI}->{qq[max table name length]} - 1 )
                      if ( length($tbl) > $default->{shared}->{DBI}->{qq[max table name length]} );
                    {
                        local $INPUT_RECORD_SEPARATOR = q{_};
                        chomp($tbl);
                    }

                    $create_tbl_stm = join q{ }, q{CREATE TABLE IF NOT EXISTS}, $tbl, q{(},
                      (
                        join q{, },
                        map { $_ . q[ ] . q[TEXT] } keys %{ $default->{tree2csv}->{init}->{q[attr that we care]} }
                      ),
                      q{)};
                    $drop_tbl_stm             = join q{ }, q{DROP TABLE IF EXISTS}, $tbl;
                    $prefix_of_insert_tbl_stm = join q{ }, q{INSERT INTO},          $tbl,
                      q[(], ( join q{, }, map { $_ } keys %{ $default->{tree2csv}->{init}->{q[attr that we care]} } ),
                      q[)], q{VALUES};

                    if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} ) {
                        $db = $cmd->{operation}->{qq[$mode]}->{output}->{value};
                    }
                    else {
                        $db = ( tempfile( UNLINK => 1, EXLOCK => 0 ) )[1];
                    }

                    $sqlite = join q{:}, q{dbi}, $default->{shared}->{DBI}->{driver}, ( join q{=}, q{dbname}, $db );
                    $dbh = DBI->connect( $sqlite, q{}, q{}, { RaiseError => 1, AutoCommit => 0 } );

                    if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} ) {
                        $dbh->do($_) foreach ( ( $drop_tbl_stm, $create_tbl_stm ) );
                        $dbh->commit;
                        map {
                            $insert_tbl_stm = join q{ }, $prefix_of_insert_tbl_stm, join q{ }, q[(],
                              ( join q{, }, map { $dbh->quote($_) } @{$_} ), q[)] . q{;};
                            $dbh->do($insert_tbl_stm);
                        } @{$result_set};

                        $dbh->commit;
                    }
                    else {
                        say q{BEGIN;};
                        say $drop_tbl_stm . q{;};
                        say $create_tbl_stm . q{;};
                        say q{COMMIT;};
                        say q{BEGIN;};
                        map {
                            $insert_tbl_stm = join q{ }, $prefix_of_insert_tbl_stm, join q{ }, q[(],
                              ( join q{, }, map { $dbh->quote($_) } @{$_} ), q[)] . q{;};
                            say $insert_tbl_stm;
                        } @{$result_set};
                        say q{COMMIT;};
                    }

                    $dbh->disconnect;
                }
                else {
                    croak join q{ }, q{The}, $mode, q{work mode does not support output ldif format.};
                }

            },
        },
    },
};

main( $cmd, $default );

sub main {
    my ( $cmd, $default ) = @_;

    process_options( $cmd, $default );
    dispatch_actions( $cmd, $default );

}

sub dispatch_actions {
    my ( $cmd, $default, ) = @_;

    my $mode = get_enabled_mode( $cmd, $default );
    croak q{None mode is enabled.} if ( !$mode );

    eval qq[$mode] . q{( $cmd, $default )};
}

sub probe {
    my ( $cmd, $default, ) = @_;
    my ( $mode, $schema, $all_objectclasses, $objectclasses );
    $mode = q{probe};

    if ( $cmd->{operation}->{qq[$mode]}->{url}->{value} ne q{} ) {
        $schema = get_schema_from_net( $cmd, $default, );
    }
    elsif ( $cmd->{operation}->{qq[$mode]}->{source}->{value} ne q{} ) {
        $schema = get_schema_from_ldif( $cmd, $default, );
    }
    else {
        croak q{You should give one of --source and --url option};
    }

    if ( scalar( @{ $cmd->{operation}->{qq[$mode]}->{is}->{value} } ) != 0 ) {
        $objectclasses = get_objectclasses_details_by_names( $schema, $cmd->{operation}->{qq[$mode]}->{is}->{value} );
        map { say dump($_); } @{$objectclasses};
    }
    else {
        $all_objectclasses = get_all_objectclasses($schema);
        map        { say; }
          sort map { $_->{name}; } @{$all_objectclasses};

    }
}

sub schema {
    my ( $cmd, $default, ) = @_;
    my ( $mode, $schema );
    $mode = q{schema};

    if ( $cmd->{operation}->{qq[$mode]}->{url}->{value} ne q{} ) {
        $schema = get_schema_from_net( $cmd, $default, );
    }
    elsif ( $cmd->{operation}->{qq[$mode]}->{source}->{value} ne q{} ) {
        $schema = get_schema_from_ldif( $cmd, $default, );
    }

    if ( $cmd->{operation}->{qq[$mode]}->{output}->{value} ne q{} ) {
        dump_schema_to_ldif( $schema, $cmd->{operation}->{qq[$mode]}->{output}->{value} );
    }
    else {
        dump_schema_to_ldif($schema);
    }
}

sub collect {
    my ( $cmd, $default ) = @_;
    my $mode = q{collect};

    my ($output_format) =
      grep { $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{value} } keys %{ $cmd->{output}->{qq[$mode]} };

    &{ $cmd->{output}->{qq[$mode]}->{qq[$output_format]} }( $cmd, $default );
}

sub tree2csv {
    my ( $cmd, $default, ) = @_;

    my $mode = q{tree2csv};

    my ($output_format) =
      grep { $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{value} } keys %{ $cmd->{output}->{qq[$mode]} };

    &{ $cmd->{output}->{qq[$mode]}->{qq[$output_format]} }( $cmd, $default );
}

sub tree2csv_rec_func_for_sql {
    my ( $row,       $init_set )   = @_;
    my ( $rec_value, $target_val ) = @{$row};
    if ( defined($rec_value) and $rec_value ) {
        if ( exists $init_set->{qq[$rec_value]} ) {
            push @{$init_set}, $target_val;
        }
    }
}

sub construct_objectclasses_tree {
    my ($schema)    = @_;
    my $objectclass = [ $schema->all_objectclasses() ];
    my $tree        = {};

    map {
        my $obj_hash_ref = $_;
        my $obj_name     = $obj_hash_ref->{name};
        if (   not exists $tree->{qq[$obj_name]}
            or not $tree->{qq[$obj_name]}->{filled}
            or !$tree->{qq[$obj_name]}->{filled} )
        {
            $tree->{qq[$obj_name]} = {} if ( not exists $tree->{qq[$obj_name]} );

            map { $tree->{qq[$obj_name]}->{qq[$_]} = {} if ( not exists $tree->{qq[$obj_name]}->{qq[$_]} ); }
              qw(type parent child);

            map {
                $tree->{qq[$obj_name]}->{type}->{qq[$_]} = {}
                  if ( not exists $tree->{qq[$obj_name]}->{type}->{qq[$_]} );
            } qw(must may);

            $tree->{qq[$obj_name]}->{filled} = 0
              if ( not exists $tree->{qq[$obj_name]}->{filled} or !exists $tree->{qq[$obj_name]}->{filled} );
        }
    } @{$objectclass};

    map {
        my $obj_hash_ref = $_;
        my $obj_name     = $obj_hash_ref->{name};

        if ( !$tree->{qq[$obj_name]}->{filled} ) {

            foreach my $attr_type ( ( q{must}, q{may}, ) ) {
                if ( exists $obj_hash_ref->{qq[$attr_type]} ) {
                    map { $tree->{qq[$obj_name]}->{type}->{qq[$attr_type]}->{qq[$_]} = 1; }
                      grep { not exists $tree->{qq[$obj_name]}->{type}->{qq[$attr_type]}->{qq[$_]}; }
                      @{ $obj_hash_ref->{qq[$attr_type]} };
                }
            }

            if ( exists $obj_hash_ref->{q[sup]} ) {
                map {
                    my $parent = $_;
                    croak q{Parent object class not found: } . $parent if ( not exists $tree->{qq[$parent]} );
                    $tree->{qq[$obj_name]}->{parent}->{qq[$parent]} = 1
                      if ( not exists $tree->{qq[$obj_name]}->{parent}->{qq[$parent]} );
                    $tree->{qq[$parent]}->{child}->{qq[$obj_name]} = 1
                      if ( not exists $tree->{qq[$parent]}->{child}->{qq[$obj_name]} );
                } @{ $obj_hash_ref->{q[sup]} };
            }
            $tree->{qq[$obj_name]}->{filled} = 1;
        }
    } @{$objectclass};

    return %{$tree} if (wantarray);
    return $tree if ( not wantarray );
}

# Return an array of hashes.
sub get_all_objectclasses {
    my ($schema) = @_;
    my $objectclass = [ $schema->all_objectclasses() ];
    return wantarray ? @{$objectclass} : $objectclass;
}

sub get_objectclasses_attrs {
    my ($objectclasses) = @_;

    croak q{Expect an array reference.} if ( ( ref $objectclasses ) ne ( ref [] ) );
    my $attr = {};

    map {
        my $object_hash_ref = $_;
        if ( exists $object_hash_ref->{must} and exists $object_hash_ref->{may} ) {
            map { $attr->{qq[$_]} = 1; }
              grep { not exists $attr->{qq[$_]}; } ( @{ $object_hash_ref->{must} }, @{ $object_hash_ref->{may} } );
        }
        elsif ( exists $object_hash_ref->{must} ) {
            map { $attr->{qq[$_]} = 1; }
              grep { not exists $attr->{qq[$_]}; } @{ $object_hash_ref->{must} };
        }
        elsif ( exists $object_hash_ref->{may} ) {
            map { $attr->{qq[$_]} = 1; }
              grep { not exists $attr->{qq[$_]}; } @{ $object_hash_ref->{may} };
        }
    } @{$objectclasses};

    delete $attr->{objectClass} if ( exists $attr->{objectClass} );

    return sort keys %{$attr} if (wantarray);
    return [ sort keys %{$attr} ] if ( not wantarray );
}

# Return an array of hashes.
sub get_objectclasses_details_by_names {
    my ( $schema, $query ) = @_;
    my $all_objectclasses = get_all_objectclasses($schema);
    my ( @objectclasses, $queries ) = ( [], {} );

    $query = [ qq{$query}, ] if ( ( ref $query ) eq q{} );

    if ( ( ref $query ) ne ( ref [] ) ) {
        croak q{Argument should be an array reference or a classobject name.};
    }

    map { $queries->{qq[$_]} = 1; } @{$query};

    @objectclasses = grep {
        my $array_item_for_objectclass = $_;
        map { $queries->{qq[$_]} = 1 if ( not exists $queries->{qq[$_]} ); } @{ $array_item_for_objectclass->{sup} }
          if ( exists $array_item_for_objectclass->{sup} );
        $queries->{qq[$array_item_for_objectclass->{name}]};
    } @{$all_objectclasses};

    return wantarray ? @objectclasses : \@objectclasses;

}

sub enable_ssl_for_ldap {
    my ( $cmd, $default, $ldap ) = @_;

    my $mode = get_enabled_mode( $cmd, $default );

    if ( $default->{shared}->{LDAP}->{ssl}->{enable} ) {
        if ( $cmd->{operation}->{qq[$mode]}->{verify}->{value} ) {
            if ( $cmd->{operation}->{qq[$mode]}->{cafile}->{value} ) {
                $ldap->start_tls( verify => q{require}, cafile => $cmd->{operation}->{qq[$mode]}->{cafile}->{value} )
                  or croak q{Failed to enable TLS};
            }
            else {
                $ldap->start_tls( verify => q{require} ) or croak q{Failed to enable TLS};
            }
        }
        else {
            $ldap->start_tls( verify => q{none} ) or croak q{Failed to enable TLS};
        }
    }
}

sub get_base_dn {
    my ( $cmd, $default, ) = @_;
    my ( $ldap, $search );
    my ($dns_field);

    my $mode = get_enabled_mode( $cmd, $default );

    if ( exists $default->{shared}->{LDAP}->{addr} ) {
        if ( $default->{shared}->{LDAP}->{addr} ne q{} ) {
            $dns_field = [ split q{\.}, $default->{shared}->{LDAP}->{addr} ];
        }
    }
    croak q{Failed to get dns field} if ( not defined($dns_field) );

    $ldap = Net::LDAP->new( $default->{shared}->{LDAP}->{addr}, port => $default->{shared}->{LDAP}->{port} )
      or croak q{Failed to create a LDAP object.};

    enable_ssl_for_ldap( $cmd, $default, $ldap );

    my $base = join q{=}, q{dc}, pop @{$dns_field};
    while (1) {
        $search = $ldap->search(
            base   => $base,
            scope  => q{base},
            filter => '(|(objectClass=*)(!(objectClass=*)))',
            attrs  => [ q{objectClass}, ]
        );

        return undef if ( scalar( @{$dns_field} ) == 0 and $search->code != 0 );
        $search->code == 0 and last;
        $base = join q{,}, ( join q{=}, q{dc}, pop @{$dns_field} ), $base;
    }
    $ldap->unbind;
    return $base;
}

sub get_ldap_from_net {
    my ( $cmd, $default ) = @_;
    my ( $server, $port );
    my ( $ldap, $search, $base, $filter, $attr );
    my ( $filter_str, $filter_is_str, $filter_maybe_str );
    my $mode = get_enabled_mode( $cmd, $default );

    $server = $default->{shared}->{LDAP}->{addr};
    $port   = $default->{shared}->{LDAP}->{port};

    $attr = [q{*}];

    if ( scalar( @{ $cmd->{operation}->{qq[$mode]}->{is}->{value} } ) > 1 ) {
        $filter_is_str =
          q[(] . q[&]
          . (
            join q{},
            map { q[(] . ( join q{=}, q[objectClass], $_ ) . q[)]; } @{ $cmd->{operation}->{qq[$mode]}->{is}->{value} }
          ) . q[)];
    }
    else {
        $filter_is_str = join q{},
          map { q[(] . ( join q{=}, q[objectClass], $_ ) . q[)]; } @{ $cmd->{operation}->{qq[$mode]}->{is}->{value} };
    }

    if ( scalar( @{ $cmd->{operation}->{qq[$mode]}->{maybe}->{value} } ) > 1 ) {
        $filter_maybe_str =
          q[(] . q[|]
          . (
            join q{},
            map { q[(] . ( join q{=}, q[objectClass], $_ ) . q[)]; }
              @{ $cmd->{operation}->{qq[$mode]}->{maybe}->{value} }
          ) . q[)];
    }
    else {
        $filter_maybe_str = join q{},
          map { q[(] . ( join q{=}, q[objectClass], $_ ) . q[)]; }
          @{ $cmd->{operation}->{qq[$mode]}->{maybe}->{value} };
    }

    if ( scalar( @{ $cmd->{operation}->{qq[$mode]}->{is}->{value} } ) ) {
        $filter_str = $filter_is_str;
    }
    elsif ( scalar( @{ $cmd->{operation}->{qq[$mode]}->{maybe}->{value} } ) ) {
        $filter_str = $filter_maybe_str;
    }

    $filter = Net::LDAP::Filter->new($filter_str);

    $base = get_base_dn( $cmd, $default );

    croak q{Cannot get a distinct name as the LDAP search base.} if ( not defined($base) );

    $ldap = Net::LDAP->new( $default->{shared}->{LDAP}->{addr}, port => $default->{shared}->{LDAP}->{port} )
      or croak q{Failed to create a LDAP object.};

    enable_ssl_for_ldap( $cmd, $default, $ldap );

    $search = $ldap->search(
        base   => $base,
        scope  => q{sub},
        filter => $filter,
        attrs  => $attr
    );

    $search->code && croak 'Failed to search' . $search->error;

    $ldap->unbind;

    return $search;
}

sub dump_schema_to_ldif {
    my ( $schema, $file ) = @_;
    if ($file) {
        $schema->dump($file);
    }
    else {
        $schema->dump;
    }
}

sub get_schema_from_ldif {
    my ( $cmd, $default ) = @_;
    my $mode = get_enabled_mode( $cmd, $default );
    my $schema = Net::LDAP::Schema->new;
    $schema->parse( $cmd->{operation}->{qq[$mode]}->{source}->{value} ) or croak $schema->error;
    return $schema;
}

sub get_schema_from_net {
    my ( $cmd, $default ) = @_;
    my ( $ldap, $schema );

    my $mode = get_enabled_mode( $cmd, $default );

    $ldap = Net::LDAP->new( $default->{shared}->{LDAP}->{addr}, port => $default->{shared}->{LDAP}->{port} )
      or croak q{Failed to create a LDAP object.};

    enable_ssl_for_ldap( $cmd, $default, $ldap );

    $ldap->bind() or croak q{Failed binding};

    $schema = $ldap->schema() or croak q{Failed to get the schema.};
    $ldap->unbind or croak q{Failed to unbind};
    return $schema;
}

sub verbose {
    if ( -t STDIN and -t STDOUT ) {
        print STDERR color(q{green}), @_, qq[\n], color(q{reset});
    }
    else {
        print @_, qq[\n];
    }
}

# The worst solution. Can we find a better way?
sub is_text_file {
    my ($file) = @_;
    my $known_types = [ q{text/x-ldif}, q{text/csv}, q{application/x-sqlite3} ];
    croak q{File not found or is not readable: } . $file . q{.} if ( not( -e $file and -r $file ) );
    my ( $magic, $text_magic ) = ( q{}, q{} );
    my ( $h, $t ) = tempfile( UNLINK => 1, EXLOCK => 0 );
    print $h q{KISS} or $text_magic = q{text/plain};
    close $h;
    $text_magic = mimetype($t);
    $magic      = mimetype($file);
    return 1 if ( $magic =~ m!^text/! );
    return $text_magic eq $magic;
}

sub usage {
    my ( $cmd, $default ) = @_;
    my $tab = 2;
    my ( $max, $wchar, $hchar, $wpixel, $hpixel, ) = qw( 10 80 42 );
    my ( $option_max_len, $option_placeholder ) = qw(0 0);
    my @modes = sort keys %{ $cmd->{operation}->{mode} };

    if ( -t STDIN and -t STDOUT ) {
        ( $wchar, $hchar, $wpixel, $hpixel ) = GetTerminalSize();
    }
    croak q{You must have at least 10 charaters.} if ( $wchar < 10 );

    $max = $max < ( $wchar / 8 ) ? $wchar / 8 : 10;

    map {
        my $mode_or_share = $_;
        map { $option_max_len = $option_max_len < length(qq{$_}) ? length(qq{$_}) : $option_max_len; }
          keys %{ $cmd->{operation}->{qq[$mode_or_share]} };
    } keys %{ $cmd->{operation} };

    $option_placeholder = length(q{--}) + $option_max_len + length(q{ });

    $Text::Wrap::columns = $wchar;

    say q{USAGE:};
    map {
        say wrap(
            q{ } x ${tab},
            q{ } x ( length( $default->{program}->{name} ) + $tab + 1 ),
            $default->{program}->{name}, $_
        );
      } (
        join( q{ }, q{--help}, ),
        join( q{ }, q{--probe},  q{--url url},     q{[--is who]} ),
        join( q{ }, q{--probe},  q{--source ldif}, q{[--is who]} ),
        join( q{ }, q{--schema}, q{--url url},     q{[--output ldif]} ),
        join( q{ }, q{--schema}, q{--source ldif}, q{[--output ldif]} ),
        join( q{ }, q{--collect}, q{--url url}, q{[--ldif]}, q{[--output file]}, q{--is who} ),
        join( q{ },
            q{--collect}, q{--url url}, q{[--sql|--csv]}, q{[--output file]},
            q{--is who}, q{[[--realtion attrbute] ...]} ),
        join( q{ },
            q{--tree2csv}, q{--sql},
            q{--init initset},
            q{--reliation relation rescursion_setting},
            q{--reliation relation},
            q{[--output file]} ),
        join( q{ },
            q{--tree2csv}, q{--csv},
            q{--init initset},
            q{--reliation relation rescursion_setting},
            q{--reliation relation},
            q{[--output file]},
            q{[--separator separator]} ),
      );
    print qq{\n};

    say wrap(
        q{}, q{}, $default->{program}->{name},
        q{has}, scalar(@modes), q{modes:},
        ( join q{ }, map { $_ } @modes ) . q{.},
        q{You can chose one of the modes by following options:}
    );

    map {
        say wrap (
            q{},
            q{ } x ( $option_placeholder + $tab ),
            q{--} . $_ . q{ } x ( $option_placeholder - length($_) ),
            $cmd->{operation}->{mode}->{$_}->{help}
        );
    } sort keys %{ $cmd->{operation}->{mode} };
    print "\n";

    say q{These modes share follwing options:};
    map {
        say wrap (
            q{},
            q{ } x ( $option_placeholder + $tab ),
            q{--} . $_ . q{ } x ( $option_placeholder - length($_) ),
            $cmd->{operation}->{shared}->{$_}->{help}
          )
    } sort keys %{ $cmd->{operation}->{shared} };
    print "\n";

    map {
        my $mode = $_;
        say join q{ }, q{The}, $mode, q{mode support follwing options:};
        map {
            say wrap (
                q{},
                q{ } x ( $option_placeholder + $tab ),
                q{--} . $_ . q{ } x ( $option_placeholder - length($_) ),
                $cmd->{operation}->{qq[$mode]}->{$_}->{help}
              )
        } sort keys %{ $cmd->{operation}->{qq[$mode]} };
        print "\n";
    } sort keys %{ $cmd->{operation}->{mode} };

    exit(0);
}

# This function is better to do some simple work.
# NEVER NEVER try to be smart on it.
# KEEP IT SIMPLE, STUPID.
sub AUTOLOAD {
    no strict;
    if ( $AUTOLOAD =~ /^main::is_mod_.*_available$/ or $AUTOLOAD =~ /^main::mod_available_status$/ ) {
        return &$AUTOLOAD;
    }
    croak "Undefined subroutine &$AUTOLOAD called";
}

sub get_enabled_mode {
    my ( $cmd, $default ) = @_;
    my ($mode) =
      grep { $cmd->{operation}->{mode}->{qq{$_}}->{value}; }
      keys %{ $cmd->{operation}->{mode} };
    return $mode ? $mode : undef;
}

sub import_mod_needed {
    my ($mods) = @_;

    croak q{Arguments should be: hash reference.}
      if ( ( ref $mods ) ne ( ref {} ) );

    map {
        my $mod = $_;
        eval exists $mods->{qq[$mod]}->{import} ? $mods->{qq[$mod]}->{import} : qq{use $mod};
    } keys %{$mods};
}

sub init_options {
    my ( $cmd, $default ) = @_;

    map {
        my $shared_or_mode_name = $_;
        map {
            croak join {}, q{No option item found for}, q{--} . $_, q{of}, $shared_or_mode_name
              if ( not exists $cmd->{options}->{qq[$_]} );
            $cmd->{operation}->{qq[$shared_or_mode_name]}->{$_} = $cmd->{options}->{qq[$_]};
        } @{ $cmd->{operation}->{qq[$shared_or_mode_name]}->{options} };
        delete $cmd->{operation}->{qq[$shared_or_mode_name]}->{options};
    } keys %{ $cmd->{operation} };
    delete $cmd->{options};

    my $init_val = {
        q{!}  => 0,
        q{s}  => q{},
        q{i}  => 0,
        q{s%} => {},
    };
    map {
        my $opts = $_;
        map {
            $opts->{qq{$_}}->{type} = q{!} if ( not exists $opts->{qq{$_}}->{type} );
            if ( not exists $opts->{qq{$_}}->{value} ) {
                $opts->{qq{$_}}->{value} =
                  exists $init_val->{ $opts->{qq{$_}}->{type} } ? $init_val->{ $opts->{qq{$_}}->{type} } : undef;
                croak join q{: }, q{Unsupport option type found}, q{--} . $_
                  if ( not defined( $opts->{qq{$_}}->{value} ) );
            }
          }
          grep { exists $opts->{qq{$_}}->{value} ? 0 : 1; } keys %{$opts};
    } values %{ $cmd->{operation} };
}

sub audit_options {
    my ( $cmd, $default ) = @_;

    my ($mode) =
      grep { $cmd->{operation}->{mode}->{qq{$_}}->{value}; }
      keys %{ $cmd->{operation}->{mode} };

    croak join q{: }, q{No enabled mode found, pls chose one among},
      ( map { q{--} . $_ } keys %{ $cmd->{operation}->{mode} } )
      if ( !$mode );

    my $is_true = sub {
        my ($you) = @_;
        my $whoami = ref $you;
        return
            $whoami
          ? $whoami eq ( ref [] )
              ? scalar( @{$you} )
              : $whoami eq ( ref {} ) ? scalar( keys %{$you} )
            : 1
          : $you;
    };

    map {
        my $opt_chk_hash_ref = $default->{qq[$_]}->{q[options checking]};
        map {
            my $checking_type = $_;
                $checking_type eq q{just one and only one} ? goto AUDIT_OPTIONS_JUST_ONE_AND_ONLY_ONE
              : $checking_type eq q{neccessary}            ? goto AUDIT_OPTIONS_NECCESSARY
              : $checking_type eq q{associate}             ? goto AUDIT_OPTIONS_ASSOCIATE
              :                                              goto AUDIT_OPTIONS_ERROR;

          AUDIT_OPTIONS_JUST_ONE_AND_ONLY_ONE:
            map {
                my $chk_item_key  = $_;
                my $chk_item      = $opt_chk_hash_ref->{qq{$checking_type}}->{qq{$chk_item_key}};
                my $chk_item_type = ref $chk_item;

                croak q{Unknown option checking value type found, expect} . q{ } . ( ref [] )
                  if ( not( $chk_item_type eq ( ref [] ) ) );

                my @enabled = grep { &$is_true( $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{value} ); }
                  grep { exists $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{value}; }
                  grep { exists $cmd->{operation}->{qq[$mode]}->{qq[$_]}; } @{$chk_item};

                croak join qq{\n}, ( join q{ }, q{More than one}, $chk_item_key, q{are enabled:} ),
                  ( map { q{ } x 4 . $_ } @enabled )
                  if ( scalar(@enabled) > 1 );

                croak join q{: }, ( join q{ }, q{Please enable one}, $chk_item_key, q{by one of following options} ),
                  ( join q{ }, map { q{--} . $_ } @{$chk_item} )
                  if ( scalar(@enabled) == 0 );
            } keys %{ $opt_chk_hash_ref->{qq{$checking_type}} };
            goto AUDIT_OPTIONS_NEXT;

          AUDIT_OPTIONS_NECCESSARY:
            map {
                croak join q{: }, q{The option must be set}, q{--} . $_
                  if ( not &$is_true( $cmd->{operation}->{qq[$mode]}->{qq{$_}}->{value} ) );
            } @{ $opt_chk_hash_ref->{qq{$checking_type}} };
            goto AUDIT_OPTIONS_NEXT;

          AUDIT_OPTIONS_ASSOCIATE:

            map {
                my $chk_item_key     = $_;
                my $chk_item         = $opt_chk_hash_ref->{qq{$checking_type}}->{qq{$chk_item_key}};
                my @failed_associate = grep {
                    &$is_true( $cmd->{operation}->{qq[$mode]}->{qq[$chk_item_key]}->{value} )
                      and ( not &$is_true( $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{value} ) );
                } @{$chk_item};

                croak join qq{\n}, ( join q{ }, q{The option}, q{--} . $chk_item_key, q{requires option} ),
                  ( join qq{\n}, map { q{ } x 4 . q{--} . $_ } @failed_associate )
                  if ( scalar(@failed_associate) != 0 );

            } keys %{ $opt_chk_hash_ref->{qq{$checking_type}} };

            goto AUDIT_OPTIONS_NEXT;

          AUDIT_OPTIONS_ERROR:
            croak join q{ }, q{Unknown options checking type found:}, $checking_type;
            goto AUDIT_OPTIONS_NEXT;

          AUDIT_OPTIONS_NEXT:
        } keys %{$opt_chk_hash_ref};
    } ( qq{$mode}, q[shared] );
}

# Unless there is a bug, I do want to fix nothing about this function.
sub select_operation_mode {
    my ( $cmd, $default ) = @_;
    my $rc            = 1;
    my @enabled_modes = qw();

    no strict 'subs';

    Getopt::Long::Configure(q{pass_through});

    my @options = map {
        my $option = $_;
        my $type   = $cmd->{operation}->{mode}->{qq{$_}}->{type};
        $option =
          $type
          ? q{'} . ( $type eq q{!} ? $option . $type : join q{=}, $option, $type ) . q{'}
          : q{'} . $option . q{'};
        join q[ => ], $option,
          (
            join q[->], ref $cmd->{operation}->{mode}->{qq{$_}}->{value} ? q[$cmd] : q[\$cmd],
            q[{operation}], q[{mode}], q[{'] . $_ . q['}], q[{value}]
          );
    } keys %{ $cmd->{operation}->{mode} };

    # We need set and process --help asap, so is --version and --verbose.
    push @options, 'q{help} => \$cmd->{operation}->{shared}->{help}->{value}',
      'q{version} => \$cmd->{operation}->{shared}->{version}->{value}',
      'q{verbose} => \$cmd->{operation}->{shared}->{verbose}->{value}';

    eval join q{ }, q{GetOptions}, q{(}, ( join q{, }, @options ), q{)};

    # From here we know whether we should verbosely output or not.
    # Here we run the usage func immediately if find --help option, so is --version.
    usage( $cmd, $default ) if ( $cmd->{operation}->{shared}->{help}->{value} );
    &{ $cmd->{operation}->{shared}->{version}->{callback} }( $cmd, $default )
      if ( $cmd->{operation}->{shared}->{version}->{value} );

    @enabled_modes =
      grep { $cmd->{operation}->{mode}->{qq{$_}}->{value} }
      keys %{ $cmd->{operation}->{mode} };

    croak join qq{\n}, q{One and only one mode could be enabled, while the following modes are enabled:},
      ( map { q{ } x 4 . $_ } @enabled_modes )
      if ( scalar(@enabled_modes) > 1 );

    @enabled_modes =
      grep { $cmd->{operation}->{mode}->{qq{$_}}->{value} }
      keys %{ $cmd->{operation}->{mode} };

    croak join q{: }, q{No enabled mode found, please chose one among},
      ( join q{ }, map { $_ } keys %{ $cmd->{operation}->{mode} } )
      if ( scalar(@enabled_modes) == 0 );

    # Welcome mode options go home.
    map { $cmd->{operation}->{shared}->{qq{$_}} = $cmd->{operation}->{mode}->{qq{$_}}; }
      keys %{ $cmd->{operation}->{mode} };

    Getopt::Long::Configure(q{no_pass_through});
    return $rc;
}

sub process_options {
    my ( $cmd, $default ) = @_;

    my $rc = 1;

    init_options( $cmd, $default );
    select_operation_mode( $cmd, $default );

    my $is_true = sub {
        my ($you) = @_;
        my $whoami = ref $you;
        return
            $whoami
          ? $whoami eq ( ref [] )
              ? scalar( @{$you} )
              : $whoami eq ( ref {} ) ? scalar( keys %{$you} )
            : 1
          : $you;
    };

    my ($mode) =
      grep { $cmd->{operation}->{mode}->{qq{$_}}->{value} }
      keys %{ $cmd->{operation}->{mode} };

    my @options = map {
        my $type = $cmd->{operation}->{shared}->{qq{$_}}->{type};
        join q{ => }, q{'} . ( $type ? $type eq q{!} ? $_ . $type : join q{=}, $_, $type : $_ ) . q{'},
          (
            join q{->}, ref $cmd->{operation}->{shared}->{qq{$_}}->{value} ? q[$cmd] : q[\$cmd],
            q[{operation}], q[{shared}], q[{'] . $_ . q['}], q[{value}]
          );
      }
      grep { not exists $cmd->{operation}->{qq{$mode}}->{qq{$_}} }
      keys %{ $cmd->{operation}->{shared} };

    push @options, map {
        my $type = $cmd->{operation}->{qq{$mode}}->{qq{$_}}->{type};
        join q{ => }, q{'} . ( $type ? $type eq q{!} ? $_ . $type : join q{=}, $_, $type : $_ ) . q{'},
          (
            join q{->}, ref $cmd->{operation}->{$mode}->{qq{$_}}->{value} ? q[$cmd] : q[\$cmd],
            q[{operation}],
            q[{'] . $mode . q['}],
            q[{'] . $_ . q['}], q[{value}]
          );
    } keys %{ $cmd->{operation}->{qq{$mode}} };

    eval join q{ }, q{GetOptions}, q{(}, ( join qq{,\n}, @options ), q{)};
    croak q{Failed when processing opionts.} if ($@);
    $rc = $@;

    foreach my $option ( keys %{ $cmd->{operation}->{shared} } ) {
        if ( exists $cmd->{$mode}->{qq[$option]} ) {
            if ( exists $cmd->{$mode}->{qq[$option]}->{value} ) {
                if ( not &$is_true( $cmd->{$mode}->{qq[$option]}->{value} ) ) {
                    grep {
                        $cmd->{operation}->{$mode}->{qq[$option]}->{qq[$_]} =
                          $cmd->{operation}->{shared}->{qq[$option]}->{qq[$_]}
                          if ( not exists $cmd->{operation}->{$mode}->{qq[$option]}->{qq[$_]} );
                    } keys %{ $cmd->{operation}->{shared}->{qq[$option]} };
                    $cmd->{operation}->{$mode}->{qq[$option]}->{value} =
                      $cmd->{operation}->{shared}->{qq[$option]}->{value};
                }
            }
            else {
                $cmd->{operation}->{$mode}->{qq[$option]} = $cmd->{operation}->{shared}->{qq[$option]};
            }
        }
        else {
            $cmd->{operation}->{$mode}->{qq[$option]} = $cmd->{operation}->{shared}->{qq[$option]};
        }

    }

    delete $cmd->{operation}->{shared};

    # OK, to run the pre audit functions.
    map { &{ $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{qq[pre audit]} }( $cmd, $default ); }
      grep { exists $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{qq[pre audit]}; }
      sort keys %{ $cmd->{operation}->{qq[$mode]} };

    audit_options( $cmd, $default );

    # OK, to run the post audit functions.
    map { &{ $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{qq[post audit]} }( $cmd, $default ); }
      grep { exists $cmd->{operation}->{qq[$mode]}->{qq[$_]}->{qq[post audit]}; }
      sort keys %{ $cmd->{operation}->{qq[$mode]} };

    return $rc;
}