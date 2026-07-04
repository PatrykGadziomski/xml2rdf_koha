#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Basename qw(basename);

use Marc2RDF::Parser qw(parse_marcxml);
use Marc2RDF::Mapper qw(map_record_to_triples);
use Marc2RDF::Serializer::Turtle qw(turtle_prefixes serialize_triple_turtle);
use FusekiClient qw(dataset_exists create_dataset upload_turtle);

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

my $INPUT_DIR   = shift @ARGV or die "Usage: $0 <input_verzeichnis>\n";
my $OUTPUT_DIR  = "$FindBin::Bin/../output";

# --- Schritt 0: Output-Verzeichnis anlegen, falls nicht vorhanden ---
mkdir $OUTPUT_DIR unless -d $OUTPUT_DIR;

# --- Schritt 1: Alle MARCXML-Dateien im Input-Verzeichnis finden ---
opendir(my $dh, $INPUT_DIR) or die "Kann Verzeichnis $INPUT_DIR nicht öffnen: $!\n";
my @files = grep { /\.marcxml$/i || /\.xml$/i } readdir($dh);
closedir($dh);

die "Keine MARCXML-Dateien in $INPUT_DIR gefunden.\n" unless @files;
print "Gefunden: " . scalar(@files) . " Datei(en) in $INPUT_DIR\n";

# --- Schritt 2: Dataset prüfen/anlegen (einmalig, nicht pro Datei) ---
print "Prüfe, ob Dataset '$DATASET' existiert...\n";
if (dataset_exists(base_url => $FUSEKI_BASE, name => $DATASET, user => $ADMIN_USER, pass => $ADMIN_PASS)) {
    print "Dataset existiert bereits.\n";
} else {
    print "Dataset existiert nicht, lege es an...\n";
    create_dataset(base_url => $FUSEKI_BASE, name => $DATASET, user => $ADMIN_USER, pass => $ADMIN_PASS);
    print "Dataset angelegt.\n";
}

# --- Schritt 3: Jede Datei konvertieren und hochladen ---
my $total_records = 0;
for my $filename (sort @files) {
    my $input_path = "$INPUT_DIR/$filename";

    my ($basename) = $filename =~ /^(.*)\.\w+$/;
    my $turtle_path = "$OUTPUT_DIR/$basename.ttl";

    print "\n--- Verarbeite $filename ---\n";

    # Konvertierung
    my @records = parse_marcxml($input_path);
    print "  $filename: " . scalar(@records) . " Datensätze geparst\n";

    open my $out, '>:encoding(UTF-8)', $turtle_path
        or die "Kann $turtle_path nicht schreiben: $!\n";
    print $out turtle_prefixes();
    for my $record (@records) {
        my @triples = map_record_to_triples($record);
        print $out serialize_triple_turtle($_) for @triples;
    }
    close $out;
    print "  -> $turtle_path geschrieben\n";

    # Upload
    print "  Lade $turtle_path nach Fuseki hoch...\n";
    upload_turtle(
        base_url => $FUSEKI_BASE,
        name     => $DATASET,
        file     => $turtle_path,
        user     => $ADMIN_USER,
        pass     => $ADMIN_PASS,
    );
    print "  Upload erfolgreich.\n";

    $total_records += scalar(@records);
}

print "\nFertig. Insgesamt $total_records Datensätze aus " . scalar(@files) . " Datei(en) importiert.\n";