package Marc2RDF::Parser;
use strict;
use warnings;
use XML::LibXML;
use Exporter 'import';
our @EXPORT_OK = qw(parse_marcxml);

# Gibt eine Liste von Record-Hashes zurück:
# { control => { '001' => '12345' },
#   fields  => [ { tag => '245', subfields => { a => 'Der Zauberberg' } }, ... ] }
sub parse_marcxml {
    my ($filename) = @_;
    my $dom = XML::LibXML->load_xml(location => $filename);

    # Namespace-Handling: Koha-MARCXML nutzt oft den MARC21-Namespace
    my $xpc = XML::LibXML::XPathContext->new($dom);
    $xpc->registerNs('marc', 'http://www.loc.gov/MARC21/slim');

    my @records;
    for my $record_node ($xpc->findnodes('//marc:record')) {
        my %rec = (control => {}, fields => []);

        for my $cf ($xpc->findnodes('.//marc:controlfield', $record_node)) {
            $rec{control}{ $cf->getAttribute('tag') } = $cf->textContent;
        }

        for my $df ($xpc->findnodes('.//marc:datafield', $record_node)) {
            my %field = ( tag => $df->getAttribute('tag'), subfields => {} );
            for my $sf ($xpc->findnodes('.//marc:subfield', $df)) {
                my $code = $sf->getAttribute('code');
                # Mehrfachbelegte Subfields (z.B. mehrere 650$a) als Array sammeln
                push @{ $field{subfields}{$code} //= [] }, $sf->textContent;
            }
            push @{ $rec{fields} }, \%field;
        }

        push @records, \%rec;
    }
    return @records;
}

1;