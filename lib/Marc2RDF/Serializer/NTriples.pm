package Marc2RDF::Serializer::NTriples;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(serialize_triple);

sub _escape_literal {
    my ($str) = @_;
    $str =~ s/\\/\\\\/g;
    $str =~ s/"/\\"/g;
    $str =~ s/\n/\\n/g;
    $str =~ s/\r/\\r/g;
    $str =~ s/\t/\\t/g;
    return $str;
}

sub serialize_triple {
    my ($triple) = @_;
    my $s = '<' . $triple->subject . '>';
    my $p = '<' . $triple->predicate . '>';
    my $o;

    if ($triple->is_literal) {
        $o = '"' . _escape_literal($triple->object) . '"';
        $o .= '@' . $triple->lang if $triple->lang;
        $o .= '^^<' . $triple->datatype . '>' if $triple->datatype;
    } else {
        $o = '<' . $triple->object . '>';
    }

    return "$s $p $o .\n";
}

1;