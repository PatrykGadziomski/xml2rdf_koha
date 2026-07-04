#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Marc2RDF::Parser qw(parse_marcxml);
use Marc2RDF::Mapper qw(map_record_to_triples);
use Marc2RDF::Serializer::Turtle qw(turtle_prefixes serialize_triple_turtle);

my $file = shift @ARGV or die "Usage: $0 bestand.marcxml\n";

my @records = parse_marcxml($file);

print turtle_prefixes();   # einmal am Anfang der Datei

for my $record (@records) {
    my @triples = map_record_to_triples($record);
    print serialize_triple_turtle($_) for @triples;
}