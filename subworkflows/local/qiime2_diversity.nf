/*
 * Diversity indices with QIIME2
 */

include { QIIME2_TREE                 } from '../../modules/local/qiime2_tree'
include { QIIME2_ALPHARAREFACTION     } from '../../modules/local/qiime2_alphararefaction'
include { QIIME2_DIVERSITY_CORE       } from '../../modules/local/qiime2_diversity_core'
include { QIIME2_DIVERSITY_ALPHA      } from '../../modules/local/qiime2_diversity_alpha'
include { QIIME2_DIVERSITY_BETA       } from '../../modules/local/qiime2_diversity_beta'
include { QIIME2_DIVERSITY_ADONIS     } from '../../modules/local/qiime2_diversity_adonis'
include { QIIME2_DIVERSITY_BETAORD    } from '../../modules/local/qiime2_diversity_betaord'

workflow QIIME2_DIVERSITY {
    take:
    ch_metadata
    ch_asv
    ch_seq
    ch_tree
    ch_stats //QIIME2_FILTERTAXA.out.tsv
    ch_metacolumn_pairwise //METADATA_PAIRWISE.out
    ch_metacolumn_all //METADATA_ALL.out
    skip_alpha_rarefaction
    skip_diversity_indices
    diversity_rarefaction_depth

    main:
    ch_versions_qiime2_diversity = Channel.empty()

    //Phylogenetic tree for beta & alpha diversities
    produce_tree = !ch_tree ? true : false
    if (produce_tree) {
        QIIME2_TREE ( ch_seq )
        ch_versions_qiime2_diversity = ch_versions_qiime2_diversity.mix(QIIME2_TREE.out.versions)
        ch_tree = QIIME2_TREE.out.qza
    }

    //Alpha-rarefaction
    if (!skip_alpha_rarefaction) {
        QIIME2_ALPHARAREFACTION ( ch_metadata, ch_asv, ch_tree, ch_stats )
        ch_versions_qiime2_diversity = ch_versions_qiime2_diversity.mix(QIIME2_ALPHARAREFACTION.out.versions)
    }

    //Calculate diversity indices
    if (!skip_diversity_indices) {

        QIIME2_DIVERSITY_CORE ( ch_metadata, ch_asv, ch_tree, ch_stats, diversity_rarefaction_depth )
        ch_versions_qiime2_diversity = ch_versions_qiime2_diversity.mix(QIIME2_DIVERSITY_CORE.out.versions)
        //Print warning if rarefaction depth is <10000
        QIIME2_DIVERSITY_CORE.out.depth.subscribe { it -> if ( it.baseName.toString().startsWith("WARNING") ) log.warn it.baseName.toString().replace("WARNING ","QIIME2_DIVERSITY_CORE: ") }

        //alpha_diversity ( ch_metadata, DIVERSITY_CORE.out.qza )
        ch_metadata
            .combine( QIIME2_DIVERSITY_CORE.out.vector.flatten() )
            .set{ ch_to_diversity_alpha }
        QIIME2_DIVERSITY_ALPHA ( ch_to_diversity_alpha )
        ch_versions_qiime2_diversity = ch_versions_qiime2_diversity.mix(QIIME2_DIVERSITY_ALPHA.out.versions)

        //beta_diversity ( ch_metadata, DIVERSITY_CORE.out.qza, ch_metacolumn_pairwise )
        ch_metadata
            .combine( QIIME2_DIVERSITY_CORE.out.distance.flatten() )
            .combine( ch_metacolumn_pairwise )
            .set{ ch_to_diversity_beta }
        QIIME2_DIVERSITY_BETA ( ch_to_diversity_beta )
        ch_versions_qiime2_diversity = ch_versions_qiime2_diversity.mix(QIIME2_DIVERSITY_BETA.out.versions)

        //adonis ( ch_metadata, DIVERSITY_CORE.out.qza )
        if (params.qiime_adonis_formula) {
            ch_qiime_adonis_formula = Channel.fromList(params.qiime_adonis_formula.tokenize(','))
            ch_metadata
                .combine( QIIME2_DIVERSITY_CORE.out.distance.flatten() )
                .combine( ch_qiime_adonis_formula )
                .set{ ch_to_diversity_beta }
            QIIME2_DIVERSITY_ADONIS ( ch_to_diversity_beta )
            ch_versions_qiime2_diversity = ch_versions_qiime2_diversity.mix(QIIME2_DIVERSITY_ADONIS.out.versions)
        }

        //beta_diversity_ordination ( ch_metadata, DIVERSITY_CORE.out.qza )
        ch_metadata
            .combine( QIIME2_DIVERSITY_CORE.out.pcoa.flatten() )
            .set{ ch_to_diversity_betaord }
        QIIME2_DIVERSITY_BETAORD ( ch_to_diversity_betaord )
        ch_versions_qiime2_diversity = ch_versions_qiime2_diversity.mix(QIIME2_DIVERSITY_BETAORD.out.versions)
    }

    emit:
    tree_qza = ch_tree
    tree_nwk = produce_tree ? QIIME2_TREE.out.nwk : []
    depth    = !skip_diversity_indices ? QIIME2_DIVERSITY_CORE.out.depth : []
    alpha    = !skip_diversity_indices ? QIIME2_DIVERSITY_ALPHA.out.alpha : []
    beta     = !skip_diversity_indices ? QIIME2_DIVERSITY_BETA.out.beta : []
    betaord  = !skip_diversity_indices ? QIIME2_DIVERSITY_BETAORD.out.beta : []
    adonis   = !skip_diversity_indices && params.qiime_adonis_formula ? QIIME2_DIVERSITY_ADONIS.out.html : []
    versions = ch_versions_qiime2_diversity
}
