#include "gd_kdtree.h"

using namespace godot;

//#define dbg godot::UtilityFunctions::print
#define dbg(...)

void GDKdTree::_bind_methods() {
  ClassDB::bind_method(D_METHOD("set_points"), &GDKdTree::set_points);
  ClassDB::bind_method(D_METHOD("find_nearest_idx"), &GDKdTree::find_nearest_idx);
  ClassDB::bind_method(D_METHOD("find_nearest_indices"), &GDKdTree::find_nearest_indices);
}

GDKdTree::GDKdTree( ) {
}

GDKdTree::~GDKdTree() {
  if( tree )
    delete tree;
}

int GDKdTree::find_nearest_idx( const Vector3& pos ) const {
  if (!tree || all.points.size() == 0) {
    return -1;
  }
  nanoflann::KNNResultSet<real_t> results(1);
  size_t return_idx = -1;
  real_t out_distance;
  results.init(&return_idx, &out_distance);
  const real_t query_pos[3] = {pos.x, pos.y, pos.z};
  tree->findNeighbors(results, query_pos, nanoflann::SearchParams(3));
  return return_idx;
}

PackedInt32Array GDKdTree::find_nearest_indices( const PackedVector3Array& in_pos ) const {
  size_t num_elems = in_pos.size();

  // Hold nearest indices
  PackedInt32Array idxs;
  idxs.resize( num_elems );

  if (!tree || all.points.size() == 0) {
    idxs.fill(-1);
    return idxs;
  }

  // Setup 
  nanoflann::KNNResultSet<real_t> results(1);
  size_t nearest_idx = -1;
  real_t out_distance;

  // This could be executed in parallel
  const Vector3* pos_addr = in_pos.ptr();
  for( size_t i=0; i<num_elems; ++i, ++pos_addr ) {
    results.init(&nearest_idx, &out_distance);
    const real_t query_pos[3] = {pos_addr->x, pos_addr->y, pos_addr->z};
    tree->findNeighbors(results, query_pos, nanoflann::SearchParams(3));
    idxs[ i ] = nearest_idx;
  }

  return idxs;
} 

void GDKdTree::set_points( const PackedVector3Array& in_pos ) {
  all.points = in_pos;
  if( tree ) {
    delete tree;
    tree = nullptr;
  }
  if (in_pos.size() == 0) {
    return;
  }
  tree = new jTree(3, all, nanoflann::KDTreeSingleIndexAdaptorParams());
}