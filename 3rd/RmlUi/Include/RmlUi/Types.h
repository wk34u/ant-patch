/*
 * This source file is part of RmlUi, the HTML/CSS Interface Middleware
 *
 * For the latest information, see http://github.com/mikke89/RmlUi
 *
 * Copyright (c) 2008-2010 CodePoint Ltd, Shift Technology Ltd
 * Copyright (c) 2019 The RmlUi Team, and contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

#ifndef RMLUI_CORE_TYPES_H
#define RMLUI_CORE_TYPES_H

#include "Config.h"

#include <cstdlib>
#include <memory>

#include "Traits.h"

namespace Rml {

// Commonly used basic types
using byte = unsigned char;
using ScriptObject = void*;
using std::size_t;

// Unicode code point
enum class Character : char32_t { Null, Replacement = 0xfffd };

}

#include "Colour.h"
#include "Vector2.h"
#include "Vector3.h"
#include "Vector4.h"
#include "Matrix4.h"
#include "ObserverPtr.h"

namespace Rml {

// Color and linear algebra
using Colourf = Colour< float, 1 >;
using Colourb = Colour< byte, 255 >;
using Vector2i = Vector2< int >;
using Vector2f = Vector2< float >;
using Vector3f = Vector3< float >;
using Vector4f = Vector4< float >;
using ColumnMajorMatrix4f = Matrix4< float, ColumnMajorStorage< float > >;
using RowMajorMatrix4f = Matrix4< float, RowMajorStorage< float > >;
using Matrix4f = RMLUI_MATRIX4_TYPE;

// Common classes
class ElementDocument;
class Element;
class ElementAnimation;
class Context;
class Event;
class Property;
class Variant;
class Transform;
class PropertyIdSet;
struct Animation;
struct Transition;
struct TransitionList;
struct Rectangle;
enum class EventId : uint16_t;
enum class PropertyId : uint8_t;
enum class FamilyId : int;

// Types for external interfaces.
using FileHandle = uintptr_t;
using TextureHandle = uintptr_t;
using CompiledGeometryHandle = uintptr_t;
using FontFaceHandle = uintptr_t;
using TextEffectsHandle = uintptr_t;

using ElementDocumentPtr = UniquePtr<ElementDocument>;
using ElementPtr = UniquePtr<Element>;

// Container types for common classes
using ElementList = Vector< Element* >;
using OwnedElementList = Vector< ElementPtr >;
using VariantList = Vector< Variant >;
using ElementAnimationList = Vector< ElementAnimation >;

using PseudoClassList = SmallUnorderedSet< String >;
using AttributeNameList = SmallUnorderedSet< String >;
using PropertyMap = UnorderedMap< PropertyId, Property >;

using Dictionary = SmallUnorderedMap< String, Variant >;
using ElementAttributes = Dictionary;
using XMLAttributes = Dictionary;

using AnimationList = Vector<Animation>;

// Additional smart pointers
using TransformPtr = SharedPtr< Transform >;

// Data binding types
class DataView;
using DataViewPtr = UniqueReleaserPtr<DataView>;
class DataController;
using DataControllerPtr = UniqueReleaserPtr<DataController>;

struct Point {
	Point() : x(0.0f), y(0.0f) {}
	Point(float x_, float y_) : x(x_), y(y_) {}
	float x;
	float y;
	void SetPoint(float x_, float y_) {
		x = x_;
		y = y_;
	}
};

struct Size {
	float w;
	float h;
	Size() : w(0.0f), h(0.0f) {}
	Size(float width, float height) : w(width), h(height) {}
	bool IsEmpty() const { return !w || !h; }
	void SetSize(float width, float height) {
		w = width;
		h = height;
	}
};

struct Rect {
	Point origin;
	Size size;
	Rect() : origin(), size() {}
	Rect(float x, float y, float width, float height) : origin(x, y), size(width, height) {}
	Rect(const Point& origin_, const Size& size_) : origin(origin_), size(size_) {}
	float x() const { return origin.x; }
	float y() const { return origin.y; }
	float width() const { return size.w; }
	float height() const { return size.h; }
	float right() const { return x() + width(); }
	float bottom() const { return y() + height(); }
	bool IsEmpty() const { return size.IsEmpty(); }
	void SetRect(float x, float y, float width, float height) {
		origin.SetPoint(x, y);
		size.SetSize(width, height);
	}
	void Union(const Rect& rect) {
		if (IsEmpty()) {
			*this = rect;
			return;
		}
		if (rect.IsEmpty()) {
			return;
		}
		float rx = std::min(x(), rect.x());
		float ry = std::min(y(), rect.y());
		float rr = std::max(right(), rect.right());
		float rb = std::max(bottom(), rect.bottom());
		SetRect(rx, ry, rr - rx, rb - ry);
	}  
	bool Contains(const Point& point) const {
		return (point.x >= x()) && (point.x < right()) && (point.y >= y()) && (point.y < bottom());
	}
};

inline bool operator==(const Point& lhs, const Point& rhs) {
	return lhs.x == rhs.x && lhs.y == rhs.y;
}
inline bool operator!=(const Point& lhs, const Point& rhs) {
	return !(lhs == rhs);
}
inline bool operator==(const Size& lhs, const Size& rhs) {
	return lhs.w == rhs.w && lhs.h == rhs.h;
}
inline bool operator!=(const Size& lhs, const Size& rhs) {
	return !(lhs == rhs);
}
inline bool operator==(const Rect& lhs, const Rect& rhs) {
	return lhs.origin == rhs.origin && lhs.size == rhs.size;
}
inline bool operator!=(const Rect& lhs, const Rect& rhs) {
	return !(lhs == rhs);
}

inline Point operator+(const Point& lhs, const Point& rhs) {
	return Point(lhs.x + rhs.x, lhs.y + rhs.y);
}
inline Point operator-(const Point& lhs, const Point& rhs) {
	return Point(lhs.x - rhs.x, lhs.y - rhs.y);
}
inline Point operator+(const Point& lhs, const Size& rhs) {
	return Point(lhs.x + rhs.w, lhs.y + rhs.h);
}
inline Point operator-(const Point& lhs, const Size& rhs) {
	return Point(lhs.x - rhs.w, lhs.y - rhs.h);
}
inline Size operator+(const Size& lhs, const Size& rhs) {
	return Size(lhs.w + rhs.w, lhs.h + rhs.h);
}
inline Size operator-(const Size& lhs, const Size& rhs) {
	return Size(lhs.w - rhs.w, lhs.h - rhs.h);
}
inline Size operator+(const Size& lhs, const Vector2f& rhs) {
	return Size(lhs.w + rhs[0], lhs.h + rhs[1]);
}
inline Size operator-(const Size& lhs, const Vector2f& rhs) {
	return Size(lhs.w - rhs[0], lhs.h - rhs[1]);
}
inline Vector2f operator+(const Vector2f& lhs, const Size& rhs) {
	return Vector2f(lhs[0] + rhs.w, lhs[1] + rhs.h);
}
inline Vector2f operator-(const Vector2f& lhs, const Size& rhs) {
	return Vector2f(lhs[0] - rhs.w, lhs[1] - rhs.h);
}


} // namespace Rml


namespace std {
// Hash specialization for enum class types (required on some older compilers)
template <> struct hash<::Rml::PropertyId> {
	using utype = typename ::std::underlying_type<::Rml::PropertyId>::type;
	size_t operator() (const ::Rml::PropertyId& t) const { ::Rml::Hash<utype> h; return h(static_cast<utype>(t)); }
};
template <> struct hash<::Rml::Character> {
	using utype = typename ::std::underlying_type<::Rml::Character>::type;
	size_t operator() (const ::Rml::Character& t) const { ::Rml::Hash<utype> h; return h(static_cast<utype>(t)); }
};
template <> struct hash<::Rml::FamilyId> {
	using utype = typename ::std::underlying_type<::Rml::FamilyId>::type;
	size_t operator() (const ::Rml::FamilyId& t) const { ::std::hash<utype> h; return h(static_cast<utype>(t)); }
};
}

#endif
