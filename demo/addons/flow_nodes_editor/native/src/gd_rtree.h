#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include "rtree.h"

using RTree3Df = RTree<int, real_t, 3>;

namespace godot {

// -------------------------------------------------
class GDRTree : public RefCounted {
  GDCLASS(GDRTree, RefCounted)

protected:
  static void _bind_methods();

  RTree3Df                 tree;
  size_t                   size = 0;

public:
  GDRTree();
  ~GDRTree();

  void clear();
  bool add( const PackedVector3Array& in_centers, const PackedVector3Array& in_sizes );
  Dictionary overlaps( const PackedVector3Array& others_centers, const PackedVector3Array& others_sizes, bool return_overlapped ) const;
  Dictionary selfPrune( const PackedVector3Array& in_centers, const PackedVector3Array& in_sizes, bool return_overlapped);
};

}
