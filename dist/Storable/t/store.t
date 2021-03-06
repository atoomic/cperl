#!./perl
#
#  Copyright (c) 1995-2000, Raphael Manfredi
#
#  You may redistribute only under the same terms as Perl 5, as specified
#  in the README file that comes with the distribution.
#

sub BEGIN {
    unshift @INC, 't';
    unshift @INC, 't/compat' if $] < 5.006002;
    require Config; import Config;
    if ($ENV{PERL_CORE} and $Config{'extensions'} !~ /\bStorable\b/) {
        print "1..0 # Skip: Storable was not built\n";
        exit 0;
    }
    require 'st-dump.pl';
}

# $Storable::DEBUGME = 1;
use Storable qw(store retrieve store_fd nstore_fd fd_retrieve);

$Storable::flags = Storable::FLAGS_COMPAT;

use Test::More tests => 24;

$a = 'toto';
$b = \$a;
$c = bless {}, CLASS;
$c->{attribute} = 'attrval';
%a = ('key', 'value', 1, 0, $a, $b, 'cvar', \$c);
@a = ('first', undef, 3, -4, -3.14159, 456, 4.5,
	$b, \$a, $a, $c, \$c, \%a);

isnt(store(\@a, "store$$"), undef);

$dumped = &dump(\@a);
isnt($dumped, undef);

$root = retrieve("store$$");
isnt($root, undef);

$got = &dump($root);
isnt($got, undef);

is($got, $dumped);

1 while unlink "store$$";

package FOO; @ISA = qw(Storable);

sub make {
	my $self = bless {};
	$self->{key} = \%main::a;
	return $self;
};

package main;

$foo = FOO->make;
isnt($foo->store("store$$"), undef);

isnt(open(OUT, '>>', "store$$"), undef);
binmode OUT;

isnt(store_fd(\@a, ::OUT), undef);
isnt(nstore_fd($foo, ::OUT), undef);
isnt(nstore_fd(\%a, ::OUT), undef);

isnt(close(OUT), undef);

isnt(open(OUT, "store$$"), undef);

$r = fd_retrieve(::OUT);
isnt($r, undef);
is(&dump($r), &dump($foo));

$r = fd_retrieve(::OUT);
isnt($r, undef);
is(&dump($r), &dump(\@a));

$r = fd_retrieve(main::OUT);
isnt($r, undef);
is(&dump($r), &dump($foo));

$r = fd_retrieve(::OUT);
isnt($r, undef);
is(&dump($r), &dump(\%a));

eval { $r = fd_retrieve(::OUT); };
isnt($@, '');

{
    my %test = (
        old_retrieve_array => "\x70\x73\x74\x30\x01\x0a\x02\x02\x02\x02\x00\x3d\x08\x84\x08\x85\x08\x06\x04\x00\x00\x01\x1b",
        old_retrieve_hash  => "\x70\x73\x74\x30\x01\x0a\x03\x00\xe8\x03\x00\x00\x81\x00\x00\x00\x01\x61",
        retrieve_code      => "\x70\x73\x74\x30\x05\x0a\x19\xf0\x00\xff\xe8\x03\x1a\x0a\x0e\x01",
    );

    for my $k (sort keys %test) {
        open my $fh, '<', \$test{$k};
        eval { Storable::fd_retrieve($fh); };
        is($?, 0, 'RT 130098:  no segfault in Storable::fd_retrieve()');
    }
}

close OUT or die "Could not close: $!";
END { 1 while unlink "store$$" }
