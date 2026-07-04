#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP qw(encode_json);

use FusekiClient qw(sparql_select);

# --- .env laden (gleiche Funktion wie in run_import.pl) ---
sub load_dotenv {
    my ($file) = @_;
    return unless -f $file;
    open my $fh, '<', $file or return;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*#/ || $line !~ /=/;
        my ($key, $value) = split /=/, $line, 2;
        $ENV{$key} = $value unless exists $ENV{$key};
    }
    close $fh;
}
load_dotenv("$FindBin::Bin/../.env");

my $FUSEKI_BASE = 'http://localhost:3030';
my $DATASET     = 'bestand';
my $ADMIN_USER  = 'admin';
my $ADMIN_PASS  = $ENV{FUSEKI_ADMIN_PASSWORD} // die "Bitte FUSEKI_ADMIN_PASSWORD setzen\n";
my $LIMIT       = 300;   # Sicherheitsgrenze, damit der Graph nicht unlesbar wird

# --- Alle Triples abfragen ---
my $query = "SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT $LIMIT";
my $result = sparql_select(
    base_url => $FUSEKI_BASE,
    name     => $DATASET,
    query    => $query,
    user     => $ADMIN_USER,
    pass     => $ADMIN_PASS,
);

my @bindings = @{ $result->{results}{bindings} };
print "Abgefragt: " . scalar(@bindings) . " Triples\n";

# --- Hilfsfunktion: aus einer IRI/einem Literal einen kurzen Anzeige-Namen machen ---
sub short_label {
    my ($value, $type) = @_;
    if ($type eq 'uri') {
        # letztes Segment nach / oder # nehmen
        (my $label = $value) =~ s{.*[/#]}{};
        return $label;
    }
    # Literal: kürzen, falls sehr lang
    my $label = $value;
    $label = substr($label, 0, 40) . '...' if length($label) > 40;
    return $label;
}

# --- Knoten und Kanten sammeln ---
my %nodes;   # id -> { id, label, group }
my @edges;

for my $row (@bindings) {
    my $s = $row->{s};
    my $p = $row->{p};
    my $o = $row->{o};

    my $s_id = $s->{value};
    my $o_id = $o->{value} . ($o->{type} eq 'literal' ? "_lit_" . scalar(keys %nodes) : '');
    # Literale eindeutig machen, falls derselbe Wert mehrfach vorkommt (z.B. gleicher Verlag)

    $nodes{$s_id} //= {
        id    => $s_id,
        label => short_label($s->{value}, $s->{type}),
        group => 'resource',
    };

    $nodes{$o_id} //= {
        id    => $o_id,
        label => short_label($o->{value}, $o->{type}),
        group => $o->{type} eq 'literal' ? 'literal' : 'resource',
    };

    push @edges, {
        from  => $s_id,
        to    => $o_id,
        label => short_label($p->{value}, 'uri'),
    };
}

my @node_list = values %nodes;
print "Graph: " . scalar(@node_list) . " Knoten, " . scalar(@edges) . " Kanten\n";

# --- HTML mit eingebetteten Daten erzeugen ---
my $nodes_json = encode_json(\@node_list);
my $edges_json = encode_json(\@edges);

my $output_path = "$FindBin::Bin/../output/graph.html";

# --- Layout berechnen: Knoten im Kreis anordnen ---
my @node_list = values %nodes;
my $n = scalar(@node_list);
my $cx = 600;   # Zentrum X
my $cy = 400;   # Zentrum Y
my $radius = 320;

my %pos;   # id -> [x, y]
my $i = 0;
for my $node (@node_list) {
    my $angle = (2 * 3.14159265 * $i) / $n;
    my $x = $cx + $radius * cos($angle);
    my $y = $cy + $radius * sin($angle);
    $pos{ $node->{id} } = [ $x, $y ];
    $i++;
}

# --- SVG-Elemente als Strings bauen ---
sub esc_xml {
    my ($s) = @_;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    return $s;
}

my $svg_edges = '';
for my $edge (@edges) {
    my ($x1, $y1) = @{ $pos{ $edge->{from} } // [$cx, $cy] };
    my ($x2, $y2) = @{ $pos{ $edge->{to} }   // [$cx, $cy] };
    my $mx = ($x1 + $x2) / 2;
    my $my = ($y1 + $y2) / 2;
    my $label = esc_xml($edge->{label});

    $svg_edges .= qq{<line x1="$x1" y1="$y1" x2="$x2" y2="$y2" stroke="#cccccc" stroke-width="1.5" />\n};
    $svg_edges .= qq{<text x="$mx" y="$my" font-size="9" fill="#888888" text-anchor="middle">$label</text>\n};
}

my $svg_nodes = '';
for my $node (@node_list) {
    my ($x, $y) = @{ $pos{ $node->{id} } };
    my $label = esc_xml($node->{label});
    my $is_literal = $node->{group} eq 'literal';
    my $color = $is_literal ? '#ffd166' : '#06a77d';

    if ($is_literal) {
        # Literale als Rechteck
        $svg_nodes .= qq{<rect x="} . ($x - 45) . qq{" y="} . ($y - 12) . qq{" width="90" height="24" rx="4" fill="$color" stroke="#333" stroke-width="0.5" />\n};
    } else {
        # Ressourcen als Kreis
        $svg_nodes .= qq{<circle cx="$x" cy="$y" r="18" fill="$color" stroke="#333" stroke-width="0.5" />\n};
    }
    $svg_nodes .= qq{<text x="$x" y="} . ($y + 32) . qq{" font-size="10" fill="#222222" text-anchor="middle">$label</text>\n};
}

# --- Komplette HTML-Datei schreiben, kein externes JS, kein CDN ---
open my $out, '>:encoding(UTF-8)', $output_path or die "Kann $output_path nicht schreiben: $!\n";
print $out <<"HTML";
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Knowledge Graph - Bestand</title>
  <style>
    body { font-family: sans-serif; margin: 0; background: #fafafa; }
    #info { position: absolute; top: 10px; left: 10px; background: white; padding: 8px 12px; border-radius: 6px; box-shadow: 0 1px 4px rgba(0,0,0,0.2); font-size: 14px; }
    svg { width: 100vw; height: 100vh; }
  </style>
</head>
<body>
  <div id="info">Knoten: $n | Kanten: ${\ scalar(@edges)}</div>
  <svg viewBox="0 0 1200 800">
    $svg_edges
    $svg_nodes
  </svg>
</body>
</html>
HTML
close $out;

print "Graph gespeichert: $output_path\n";
print "Oeffne die Datei direkt im Browser (kein Server, kein CDN noetig): $output_path\n";