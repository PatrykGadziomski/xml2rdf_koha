package Marc2RDF::Mapper;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(map_record_to_triples);
use Marc2RDF::Triple;

# --- Basis-Namensräume ---
my $BASE_URI    = 'http://example.org/record/';
my $AUTHOR_URI  = 'http://example.org/author/';
my $SUBJECT_URI = 'http://example.org/subject/';

# --- Häufig genutzte Prädikate ---
my $DC_TITLE       = 'http://purl.org/dc/elements/1.1/title';
my $DC_CREATOR     = 'http://purl.org/dc/elements/1.1/creator';
my $DC_CONTRIBUTOR = 'http://purl.org/dc/elements/1.1/contributor';
my $DC_PUBLISHER   = 'http://purl.org/dc/elements/1.1/publisher';
my $DC_DATE        = 'http://purl.org/dc/elements/1.1/date';
my $DC_IDENTIFIER  = 'http://purl.org/dc/elements/1.1/identifier';
my $DC_SUBJECT     = 'http://purl.org/dc/elements/1.1/subject';
my $FOAF_NAME      = 'http://xmlns.com/foaf/0.1/name';
my $SKOS_LABEL     = 'http://www.w3.org/2004/02/skos/core#prefLabel';

# Normalisiert einen Namen/Begriff zu einem URL-sicheren Slug
# "Mann, Thomas" -> "mann-thomas"
sub _slugify {
    my ($text) = @_;
    my $slug = lc($text);
    $slug =~ s/,//g;
    $slug =~ s/[^a-z0-9\s-]//g;
    $slug =~ s/\s+/-/g;
    $slug =~ s/^-+|-+$//g;
    return $slug;
}

sub map_record_to_triples {
    my ($record) = @_;
    my @triples;

    my $id = $record->{control}{'001'};
    return () unless $id;
    my $subject = $BASE_URI . $id;

    for my $field (@{ $record->{fields} }) {
        my $tag = $field->{tag};

        # --- 245: Titel (bleibt Literal) ---
        if ($tag eq '245' && exists $field->{subfields}{a}) {
            push @triples, Marc2RDF::Triple->new(
                $subject, $DC_TITLE, $field->{subfields}{a}[0], is_literal => 1
            );
        }

        # --- 100: Hauptautor (wird zur IRI) ---
        if ($tag eq '100' && exists $field->{subfields}{a}) {
            for my $name (@{ $field->{subfields}{a} }) {
                my $author_iri = $AUTHOR_URI . _slugify($name);

                push @triples, Marc2RDF::Triple->new(
                    $subject, $DC_CREATOR, $author_iri, is_literal => 0
                );
                push @triples, Marc2RDF::Triple->new(
                    $author_iri, $FOAF_NAME, $name, is_literal => 1
                );
            }
        }

        # --- 700: Weitere Mitwirkende (Übersetzer, Herausgeber, etc. -> auch IRI) ---
        if ($tag eq '700' && exists $field->{subfields}{a}) {
            for my $name (@{ $field->{subfields}{a} }) {
                my $person_iri = $AUTHOR_URI . _slugify($name);

                push @triples, Marc2RDF::Triple->new(
                    $subject, $DC_CONTRIBUTOR, $person_iri, is_literal => 0
                );
                push @triples, Marc2RDF::Triple->new(
                    $person_iri, $FOAF_NAME, $name, is_literal => 1
                );
            }
        }

        # --- 260/264: Verlag + Erscheinungsjahr (bleiben Literale) ---
        if (($tag eq '260' || $tag eq '264')) {
            if (exists $field->{subfields}{b}) {
                push @triples, Marc2RDF::Triple->new(
                    $subject, $DC_PUBLISHER, $field->{subfields}{b}[0], is_literal => 1
                );
            }
            if (exists $field->{subfields}{c}) {
                push @triples, Marc2RDF::Triple->new(
                    $subject, $DC_DATE, $field->{subfields}{c}[0], is_literal => 1
                );
            }
        }

        # --- 020: ISBN (bleibt Literal) ---
        if ($tag eq '020' && exists $field->{subfields}{a}) {
            push @triples, Marc2RDF::Triple->new(
                $subject, $DC_IDENTIFIER, $field->{subfields}{a}[0], is_literal => 1
            );
        }

        # --- 650: Schlagworte (werden zur IRI, damit gleiche Themen sich verbinden) ---
        if ($tag eq '650' && exists $field->{subfields}{a}) {
            for my $term (@{ $field->{subfields}{a} }) {
                my $subject_iri = $SUBJECT_URI . _slugify($term);

                push @triples, Marc2RDF::Triple->new(
                    $subject, $DC_SUBJECT, $subject_iri, is_literal => 0
                );
                push @triples, Marc2RDF::Triple->new(
                    $subject_iri, $SKOS_LABEL, $term, is_literal => 1
                );
            }
        }
    }

    return @triples;
}

1;