package Marc2RDF::Serializer::Turtle;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(turtle_prefixes serialize_triple_turtle);

# Prefix-Tabelle: Kürzel -> Namespace-IRI
my %PREFIXES = (
    dc  => 'http://purl.org/dc/elements/1.1/',
);

# Gibt den @prefix-Block als String zurück (einmal am Dateianfang ausgeben)
sub turtle_prefixes {
    my $out = '';
    for my $short (sort keys %PREFIXES) {
        $out .= "\@prefix $short: <$PREFIXES{$short}> .\n";
    }
    $out .= "\n";
    return $out;
}

# Versucht eine IRI durch prefix:kürzel abzukürzen, sonst volle <IRI>
sub _abbreviate {
    my ($iri) = @_;
    for my $short (keys %PREFIXES) {
        my $ns = $PREFIXES{$short};
        if (index($iri, $ns) == 0) {
            my $local = substr($iri, length($ns));
            return "$short:$local";
        }
    }
    return "<$iri>";   # kein passender Prefix gefunden -> volle IRI
}

sub _escape_literal {
    my ($str) = @_;
    $str =~ s/\\/\\\\/g;
    $str =~ s/"/\\"/g;
    $str =~ s/\n/\\n/g;
    $str =~ s/\r/\\r/g;
    $str =~ s/\t/\\t/g;
    return $str;
}

sub serialize_triple_turtle {
    my ($triple) = @_;
    my $s = "<" . $triple->subject . ">";       # Subjekt bleibt volle IRI (einfacher)
    my $p = _abbreviate($triple->predicate);     # Prädikat wird abgekürzt, falls möglich

    my $o;
    if ($triple->is_literal) {
        $o = '"' . _escape_literal($triple->object) . '"';
        $o .= '@' . $triple->lang if $triple->lang;
        $o .= '^^<' . $triple->datatype . '>' if $triple->datatype;
    } else {
        $o = _abbreviate($triple->object);
    }

    return "$s $p $o .\n";
}

1;