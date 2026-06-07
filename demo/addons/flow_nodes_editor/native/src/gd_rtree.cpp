#include "gd_rtree.h"
#include <godot_cpp/variant/utility_functions.hpp>
#include "bit_buffer.h"

using namespace godot;

//#define dbg godot::UtilityFunctions::print
#define dbg(...)

void GDRTree::_bind_methods() {
  ClassDB::bind_method(D_METHOD("clear"), &GDRTree::clear);
  ClassDB::bind_method(D_METHOD("add", "centers", "sizes"), &GDRTree::add);
  ClassDB::bind_method(D_METHOD("self_prune", "centers", "sizes", "return_overlapped"), &GDRTree::selfPrune);
  ClassDB::bind_method(D_METHOD("overlaps", "others_centers", "others_sizes", "return_overlapped"), &GDRTree::overlaps);
}

GDRTree::GDRTree() {
}

GDRTree::~GDRTree() {
}

void GDRTree::clear() {
  tree.RemoveAll();
  size = 0;
}

bool GDRTree::add( const PackedVector3Array& in_centers, const PackedVector3Array& in_sizes ) {
  
  if( in_centers.size() != in_sizes.size() )
    return false;

  const Vector3 *centers_data = in_centers.ptr();
  const Vector3 *sizes_data = in_sizes.ptr();

  int id = size;
  const size_t i_max = in_centers.size();
  for( size_t i=0; i<i_max; ++i, ++id ) {
    const real_t* center = &in_centers[i].x;
    const real_t* size = &sizes_data[i].x;
    dbg( "Inserting ", id, " : ", center[0], ", ", center[1], ", ", center[2], ", ", size[0], ", ", size[1], ", ", size[2] );

    const real_t half = static_cast<real_t>(0.5);
    real_t pmin[3] = { center[0] - size[0] * half, center[1] - size[1] * half, center[2] - size[2] * half };
    real_t pmax[3] = { center[0] + size[0] * half, center[1] + size[1] * half, center[2] + size[2] * half };
    tree.Insert(pmin, pmax, id);
  }

  size += i_max;
  return true;
}

static Dictionary createResult( bool result, int size, const BitBuffer& bit_buffer, bool return_overlapped ) {
  const int my_max = size;
  PackedInt32Array idxs_overlapped;
  for( int i=0; i<my_max; ++i ) {
    if( bit_buffer.get_bit( i ) == return_overlapped )
      idxs_overlapped.push_back( i );
  }

  Dictionary ret;
  ret["result"] = result;
  ret["idxs_overlapped"] = idxs_overlapped;
  return ret;
}

Dictionary GDRTree::selfPrune( const PackedVector3Array& in_centers, const PackedVector3Array& in_sizes, bool return_overlapped ) {
  BitBuffer bb_my_idxs_overlapped_by_others;
  bool result = false;
  int tree_size = 0;
  const int i_max = (int)in_centers.size();
  if( in_centers.size() == in_sizes.size() ) {
    const Vector3 *centers_data = in_centers.ptr();
    const Vector3 *sizes_data = in_sizes.ptr();

    int insert_id = size;
    for( int i=0; i<i_max; ++i ) {
      const real_t* center = &in_centers[i].x;
      const real_t* size = &sizes_data[i].x;
      const real_t half = static_cast<real_t>(0.5);
      real_t pmin[3] = { center[0] - size[0] * half, center[1] - size[1] * half, center[2] - size[2] * half };
      real_t pmax[3] = { center[0] + size[0] * half, center[1] + size[1] * half, center[2] + size[2] * half };
      dbg( "selfPrune.Testing ", i ); //, " : ", center[0], ", ", center[1], ", ", center[2], ", ", size[0], ", ", size[1], ", ", size[2] );

      // Check if center + Size is empty
      if( tree.Search(pmin, pmax, [&](const int& id) -> bool {
        dbg( "  Overlaps of ", i, " with!! ", id );
        return true;
        })) {
        bb_my_idxs_overlapped_by_others.set_bit( i, true );
        continue;
      }

      // If no intersection found... insert it
      tree.Insert(pmin, pmax, insert_id);
      insert_id += 1;
      tree_size += 1;
    }
    size = insert_id;
    result = true;
  }
  return createResult( result, i_max, bb_my_idxs_overlapped_by_others, return_overlapped);
}

Dictionary GDRTree::overlaps( const PackedVector3Array& others_centers, const PackedVector3Array& others_sizes, bool return_overlapped ) const {

  BitBuffer bb_my_idxs_overlapped_by_others;
  //PackedInt32Array other_idxs_overlapping_me;

  bool result = false;
  if( others_centers.size() == others_sizes.size() ) {
    const size_t i_max = others_centers.size();
    for( size_t i=0; i<i_max; ++i ) {
      
      const real_t* center = &others_centers[i].x;
      const real_t* size = &others_sizes[i].x;
      dbg( "Overlap ", (int)i ); //, " : ", center[0], ", ", center[1], ", ", center[2], ", ", size[0], ", ", size[1], ", ", size[2] );

      const real_t half = static_cast<real_t>(0.5);
      real_t pmin[3] = { center[0] - size[0] * half, center[1] - size[1] * half, center[2] - size[2] * half };
      real_t pmax[3] = { center[0] + size[0] * half, center[1] + size[1] * half, center[2] + size[2] * half };

      if( tree.Search(pmin, pmax, [&](const int& id) -> bool {
        dbg( "  Overlaps of ", (int)i, " with!! ", (int)id );
        bb_my_idxs_overlapped_by_others.set_bit( id, true );
        return true;
        })) {
        //other_idxs_overlapping_me.push_back( i );
      } else {
        //dbg( "  no overlap deletected for ", i );
      }
    }
    result = true;
  }

  return createResult( result, size, bb_my_idxs_overlapped_by_others, return_overlapped);
}
