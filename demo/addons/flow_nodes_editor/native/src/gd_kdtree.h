#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include "nanoflann.hpp"

namespace godot {

// -------------------------------------------------
class GDKdTree : public RefCounted {
  GDCLASS(GDKdTree, RefCounted)

protected:
  static void _bind_methods();

  // Container of all the points, following the requirements of the 
  // nanoflann::KDTreeSingleIndexDynamicAdaptor
  struct PointCloud {
    PackedVector3Array points;
    PointCloud() {
    }
    size_t kdtree_get_point_count() const {
      return points.size();
    }
    real_t kdtree_get_pt(const size_t idx, const size_t dim) const {
      return *(&points[idx].x + dim);
    }
    template <class BBOX>
    bool kdtree_get_bbox(BBOX& /* bb */) const { return false; }
  };

  typedef nanoflann::KDTreeSingleIndexDynamicAdaptor<
    nanoflann::L2_Simple_Adaptor<real_t, PointCloud >,
    PointCloud,
    3
  > jTree;

  PointCloud all;
  jTree*     tree = nullptr;

public:
  GDKdTree( );
  ~GDKdTree();
  
  void set_points( const PackedVector3Array& in_pos );
  int find_nearest_idx( const Vector3& pos ) const;
  PackedInt32Array find_nearest_indices( const PackedVector3Array& in_pos ) const;
};

}
