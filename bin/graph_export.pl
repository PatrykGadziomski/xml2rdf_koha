#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP qw(encode_json);

use FusekiClient qw(sparql_select);

# --- .env laden ---
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

# --- Konfiguration ---
my $FUSEKI_BASE = 'http://localhost:3030';
my $DATASET     = 'bestand';
my $ADMIN_USER  = 'admin';
my $ADMIN_PASS  = $ENV{FUSEKI_ADMIN_PASSWORD} // die "Bitte FUSEKI_ADMIN_PASSWORD setzen\n";
my $LIMIT       = 2000;

# --- Alle Triples abfragen ---
my $query = "SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT $LIMIT";
my $result = sparql_select(
    base_url => $FUSEKI_BASE, name => $DATASET, query => $query,
    user => $ADMIN_USER, pass => $ADMIN_PASS,
);
my @bindings = @{ $result->{results}{bindings} };
print "Abgefragt: " . scalar(@bindings) . " Triples\n";

# --- Hilfsfunktionen ---
sub short_label {
    my ($value, $type) = @_;
    if ($type eq 'uri') {
        (my $label = $value) =~ s{.*[/#]}{};
        return $label;
    }
    my $label = $value;
    $label = substr($label, 0, 30) . '...' if length($label) > 30;
    return $label;
}

# Ordnet einen Knoten einer Gruppe zu, anhand der URI-Struktur
sub classify_node {
    my ($value, $type) = @_;
    return 'literal' if $type eq 'literal';
    return 'author'  if $value =~ m{/author/};
    return 'subject' if $value =~ m{/subject/};
    return 'book'    if $value =~ m{/record/};
    return 'resource';   # Fallback fuer alles Unerwartete
}

# --- Knoten + Kanten aus den SPARQL-Ergebnissen sammeln ---
my %nodes;
my @edges;
my $literal_counter = 0;

for my $row (@bindings) {
    my ($s, $p, $o) = ($row->{s}, $row->{p}, $row->{o});
    my $s_id = $s->{value};
    my $o_id = $o->{type} eq 'literal'
        ? $o->{value} . "__lit" . ($literal_counter++)   # Literale eindeutig machen
        : $o->{value};

    $nodes{$s_id} //= {
        id    => $s_id,
        label => short_label($s->{value}, $s->{type}),
        group => classify_node($s->{value}, $s->{type}),
    };
    $nodes{$o_id} //= {
        id    => $o_id,
        label => short_label($o->{value}, $o->{type}),
        group => classify_node($o->{value}, $o->{type}),
    };

    push @edges, { from => $s_id, to => $o_id, label => short_label($p->{value}, 'uri') };
}

my @node_list = values %nodes;
print "Graph: " . scalar(@node_list) . " Knoten, " . scalar(@edges) . " Kanten\n";

# --- Alles als JSON fuer JS einbetten ---
my $nodes_json = encode_json(\@node_list);
my $edges_json = encode_json(\@edges);

my $output_path = "$FindBin::Bin/../output/graph.html";
open my $out, '>:encoding(UTF-8)', $output_path or die "Kann $output_path nicht schreiben: $!\n";

print $out <<"HTML";
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Knowledge Graph - Bestand</title>
<style>
  body { font-family: sans-serif; margin: 0; background: #fafafa; }
  #info { position: absolute; top: 10px; left: 10px; background: white; padding: 8px 12px;
          border-radius: 6px; box-shadow: 0 1px 4px rgba(0,0,0,0.2); font-size: 13px; max-width: 320px; }
  #legend { margin-top: 8px; font-size: 12px; }
  #legend span { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 4px; vertical-align: middle; }
  svg { width: 100vw; height: 100vh; display: block; }
  .node-book     { fill: #06a77d; stroke: #333; stroke-width: 0.5; cursor: grab; }
  .node-author   { fill: #d64550; stroke: #333; stroke-width: 0.5; cursor: grab; }
  .node-subject  { fill: #3d5a80; stroke: #333; stroke-width: 0.5; cursor: grab; }
  .node-literal  { fill: #ffd166; stroke: #333; stroke-width: 0.5; cursor: grab; }
  .node-resource { fill: #999999; stroke: #333; stroke-width: 0.5; cursor: grab; }
  .node-label    { font-size: 10px; fill: #222; text-anchor: middle; pointer-events: none; }
  .edge-line     { stroke: #cccccc; stroke-width: 1.3; }
</style>
</head>
<body>
<div id="info">
  <span id="stats"></span>
  <div id="legend">
    <span style="background:#06a77d"></span> Buch &nbsp;
    <span style="background:#d64550"></span> Autor &nbsp;
    <span style="background:#3d5a80"></span> Thema &nbsp;
    <span style="background:#ffd166"></span> Sonstiges
  </div>
</div>
<svg id="graph"></svg>

<script>
const allNodes = $nodes_json;
const allEdges = $edges_json;

const nodeMap = {};
allNodes.forEach(n => nodeMap[n.id] = n);

// --- Physik-Zustand: jeder Knoten bekommt Position + Geschwindigkeit ---
const W = 1400, H = 900;
allNodes.forEach(n => {
    n.x = W/2 + (Math.random() - 0.5) * 400;
    n.y = H/2 + (Math.random() - 0.5) * 400;
    n.vx = 0;
    n.vy = 0;
});

// --- Physik-Parameter ---
const REPULSION       = 12000;
const SPRING_LENGTH   = 140;
const SPRING_STRENGTH = 0.02;
const DAMPING         = 0.85;
const CENTER_PULL     = 0.002;

function simulationStep() {
    for (let i = 0; i < allNodes.length; i++) {
        for (let j = i + 1; j < allNodes.length; j++) {
            const a = allNodes[i], b = allNodes[j];
            let dx = a.x - b.x, dy = a.y - b.y;
            let distSq = dx*dx + dy*dy || 0.01;
            let dist = Math.sqrt(distSq);
            let force = REPULSION / distSq;
            let fx = (dx / dist) * force;
            let fy = (dy / dist) * force;
            a.vx += fx; a.vy += fy;
            b.vx -= fx; b.vy -= fy;
        }
    }

    allEdges.forEach(e => {
        const a = nodeMap[e.from], b = nodeMap[e.to];
        if (!a || !b) return;
        let dx = b.x - a.x, dy = b.y - a.y;
        let dist = Math.sqrt(dx*dx + dy*dy) || 0.01;
        let displacement = dist - SPRING_LENGTH;
        let force = displacement * SPRING_STRENGTH;
        let fx = (dx / dist) * force;
        let fy = (dy / dist) * force;
        a.vx += fx; a.vy += fy;
        b.vx -= fx; b.vy -= fy;
    });

    allNodes.forEach(n => {
        if (n.dragging) return;
        n.vx += (W/2 - n.x) * CENTER_PULL;
        n.vy += (H/2 - n.y) * CENTER_PULL;
        n.vx *= DAMPING;
        n.vy *= DAMPING;
        n.x += n.vx;
        n.y += n.vy;
    });
}

// --- SVG-Elemente einmalig anlegen ---
const SVG_NS = 'http://www.w3.org/2000/svg';
const svg = document.getElementById('graph');
svg.setAttribute('viewBox', '0 0 ' + W + ' ' + H);

function svgEl(tag, attrs) {
    const el = document.createElementNS(SVG_NS, tag);
    for (const k in attrs) el.setAttribute(k, attrs[k]);
    return el;
}

const groupClass = {
    book:     'node-book',
    author:   'node-author',
    subject:  'node-subject',
    literal:  'node-literal',
    resource: 'node-resource'
};

const edgeLines = allEdges.map(() => {
    const line = svgEl('line', { class: 'edge-line' });
    svg.appendChild(line);
    return line;
});

const nodeShapes = allNodes.map(n => {
    let shape;
    const cls = groupClass[n.group] || 'node-resource';
    if (n.group === 'literal') {
        shape = svgEl('rect', { class: cls, width: 100, height: 24, rx: 4 });
    } else {
        shape = svgEl('circle', { class: cls, r: 16 });
    }
    shape.addEventListener('mousedown', evt => startDrag(evt, n));
    svg.appendChild(shape);

    const label = svgEl('text', { class: 'node-label' });
    label.textContent = n.label;
    svg.appendChild(label);

    return { shape, label };
});

function draw() {
    allEdges.forEach((e, i) => {
        const a = nodeMap[e.from], b = nodeMap[e.to];
        if (!a || !b) return;
        const line = edgeLines[i];
        line.setAttribute('x1', a.x);
        line.setAttribute('y1', a.y);
        line.setAttribute('x2', b.x);
        line.setAttribute('y2', b.y);
    });

    allNodes.forEach((n, i) => {
        const { shape, label } = nodeShapes[i];
        if (n.group === 'literal') {
            shape.setAttribute('x', n.x - 50);
            shape.setAttribute('y', n.y - 12);
        } else {
            shape.setAttribute('cx', n.x);
            shape.setAttribute('cy', n.y);
        }
        label.setAttribute('x', n.x);
        label.setAttribute('y', n.y + 30);
    });
}

function animate() {
    simulationStep();
    draw();
    requestAnimationFrame(animate);
}

// --- Dragging ---
let dragOffset = { x: 0, y: 0 };
let dragNode = null;

function startDrag(evt, n) {
    dragNode = n;
    n.dragging = true;
    const pt = toSvgCoords(evt);
    dragOffset.x = pt.x - n.x;
    dragOffset.y = pt.y - n.y;
    evt.stopPropagation();
}

function toSvgCoords(evt) {
    const rect = svg.getBoundingClientRect();
    const scaleX = W / rect.width;
    const scaleY = H / rect.height;
    return {
        x: (evt.clientX - rect.left) * scaleX,
        y: (evt.clientY - rect.top) * scaleY
    };
}

document.addEventListener('mousemove', evt => {
    if (!dragNode) return;
    const pt = toSvgCoords(evt);
    dragNode.x = pt.x - dragOffset.x;
    dragNode.y = pt.y - dragOffset.y;
    dragNode.vx = 0;
    dragNode.vy = 0;
});

document.addEventListener('mouseup', () => {
    if (dragNode) dragNode.dragging = false;
    dragNode = null;
});

document.getElementById('stats').textContent =
    'Knoten: ' + allNodes.length + ' | Kanten: ' + allEdges.length;

animate();
</script>
</body>
</html>
HTML
close $out;

print "Graph gespeichert: $output_path\n";
print "Oeffne die Datei direkt im Browser: $output_path\n";