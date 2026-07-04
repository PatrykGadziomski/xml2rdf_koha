package Marc2RDF::Mapper;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(map_record_to_triples); 
use Marc2RDF::Triple;

# Mapping-Tabelle: MARC-Tag+Subfield -> RDF-Prädikat
# Format: [ tag, subfield_code, predicate_iri, is_repeatable ]
my @MAPPING = (
    ['245', 'a', 'http://purl.org/dc/elements/1.1/title',     0],
    ['100', 'a', 'http://purl.org/dc/elements/1.1/creator',   0],
    ['700', 'a', 'http://purl.org/dc/elements/1.1/contributor', 1],
    ['260', 'b', 'http://purl.org/dc/elements/1.1/publisher', 0],
    ['260', 'c', 'http://purl.org/dc/elements/1.1/date',      0],
    ['020', 'a', 'http://purl.org/dc/elements/1.1/identifier',0],
    ['650', 'a', 'http://purl.org/dc/elements/1.1/subject',   1],
);

my $BASE_URI = 'http://example.org/record/';

sub map_record_to_triples {
    my ($record) = @_;
    my @triples;

    my $id = $record->{control}{'001'};
    return () unless $id;

    my $subject = $BASE_URI . $id;

    for my $field (@{ $record->{fields} }) {
        for my $rule (@MAPPING) {
            my ($tag, $code, $predicate, $repeatable) = @$rule;
            next unless $field->{tag} eq $tag;
            next unless exists $field->{subfields}{$code};

            my @values = @{ $field->{subfields}{$code} };
            @values = ($values[0]) unless $repeatable;  # nur erstes nehmen, falls nicht wiederholbar

            for my $value (@values) {
                push @triples, Marc2RDF::Triple->new(
                    $subject, $predicate, $value, is_literal => 1
                );
            }
        }
    }
    return @triples;
}

1;