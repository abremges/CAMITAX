#!/usr/bin/env nextflow
camitax_version = 'v0.1.0'
println """
 ▄████▄   ▄▄▄       ███▄ ▄███▓ ██▓▄▄▄█████▓ ▄▄▄      ▒██   ██▒
▒██▀ ▀█  ▒████▄    ▓██▒▀█▀ ██▒▓██▒▓  ██▒ ▓▒▒████▄    ▒▒ █ █ ▒░
▒▓█    ▄ ▒██  ▀█▄  ▓██    ▓██░▒██▒▒ ▓██░ ▒░▒██  ▀█▄  ░░  █   ░
▒▓▓▄ ▄██▒░██▄▄▄▄██ ▒██    ▒██ ░██░░ ▓██▓ ░ ░██▄▄▄▄██  ░ █ █ ▒
▒ ▓███▀ ░ ▓█   ▓██▒▒██▒   ░██▒░██░  ▒██▒ ░  ▓█   ▓██▒▒██▒ ▒██▒
░ ░▒ ▒  ░ ▒▒   ▓▒█░░ ▒░   ░  ░░▓    ▒ ░░    ▒▒   ▓▒█░▒▒ ░ ░▓ ░
  ░  ▒     ▒   ▒▒ ░░  ░      ░ ▒ ░    ░      ▒   ▒▒ ░░░   ░▒ ░
░          ░   ▒   ░      ░    ▒ ░  ░        ░   ▒    ░    ░
░ ░            ░  ░       ░    ░                 ░  ░ ░    ░
░                                    ${camitax_version?:''}
"""

genomes = Channel.fromPath("input/*.fasta").collect()
genomes.subscribe { println "Input genomes: " + it }

process extract_rRNA {

	publishDir 'data'

	input:
	each genome from genomes

	output:
//	file "${genome.baseName}.barrnap.gff"
//	file "${genome.baseName}.prokka.*"
	file "${genome.baseName}.16S_rRNA.fasta" into rRNA_fasta

//	barrnap ${genome} > ${genome.baseName}.barrnap.gff
//	prokka --noanno --cpus 1 --rnammer --outdir . --force --prefix ${genome.baseName}.prokka --locustag PROKKA ${genome}
	"""
	barrnap --threads 1 ${genome} > ${genome.baseName}.barrnap.gff
	bedtools getfasta -fi ${genome} -bed <(grep "product=16S ribosomal RNA" ${genome.baseName}.barrnap.gff)  > ${genome.baseName}.16S_rRNA.fasta
	"""
}

process annotate_rRNA {

	publishDir 'data'

	input:
	file fasta from rRNA_fasta

	output:
	file "${fasta.baseName}.dada2.txt" into silva_lineage

	"""
	#!/usr/bin/env RScript

	library(dada2)
	library("Biostrings")
	set.seed(42)

	fastaFile <- readDNAStringSet("${fasta}")
	tt <- addSpecies(assignTaxonomy(paste(fastaFile), "$baseDir/db/dada2/silva_nr_v132_train_set_bac_arc.fa.gz"), "$baseDir/db/dada2/silva_species_assignment_v132.fa.gz")
	write.table(tt, "${fasta.baseName}.dada2.txt", quote=FALSE, sep=";", row.names=F, col.names=F)
	"""
}

process to_ncbi_taxonomy {

	publishDir 'data'

	input:
	file lineage from silva_lineage

	output:
	file "${lineage.baseName}.ncbi.txt" into ncbi_lineage

	"""
	#!/usr/bin/env python3

	import gzip

	name_to_ncbi_id = {}
	ncbi_id_to_lineage = {}

	with gzip.open("$baseDir/db/taxonomy/rankedlineage.dmp.gz") as f:
		for line in f:
			line = ''.join(line.decode('utf-8').rstrip().split('\t'))
			(id, name, species, genus, family, order, class_, phylum, _, superkingdom, _) = line.split('|')
			if not superkingdom:
				superkingdom = name
			elif not phylum:
				phylum = name
			elif not class_:
				class_ = name
			elif not order:
				order = name
			elif not family:
				family = name
			elif not genus:
				genus = name
			elif not species:
				species = name
			name_to_ncbi_id[name] = id
			ncbi_id_to_lineage[id] = "{};{};{};{};{};{};{}".format(superkingdom, phylum, class_, order, family, genus, species)

	with open("${lineage}") as f:
		with open("${lineage.baseName}.ncbi.txt", 'w') as g:
			for line in f:
				line = line.rstrip()
				taxa = line.split(';')
				ncbi_id = 1
				lineage = ";;;;;;"
				if ' '.join(taxa[-2:]) in name_to_ncbi_id:
					ncbi_id = name_to_ncbi_id[' '.join(taxa[-2:])]
				else:
					for taxon in reversed(taxa[:-1]):
						if taxon in name_to_ncbi_id:
							ncbi_id = name_to_ncbi_id[taxon]
							break;
				if ncbi_id in ncbi_id_to_lineage:
					lineage = ncbi_id_to_lineage[ncbi_id]
				g.write("{}\\t{}\\n".format(ncbi_id, lineage))
	"""
}
