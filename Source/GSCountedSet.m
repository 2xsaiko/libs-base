/** Concrete implementation of NSCountedSet based on GNU Set class
   Copyright (C) 1998,2000 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Created: October 1998

   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.
   */

#import "common.h"
#import "Foundation/NSSet.h"
#import "Foundation/NSAutoreleasePool.h"
#import "Foundation/NSEnumerator.h"
#import "Foundation/NSException.h"
#import "Foundation/NSPortCoder.h"

#import "GSPrivate.h"

#define	GSI_MAP_RETAIN_VAL(M, X)	
#define	GSI_MAP_RELEASE_VAL(M, X)	
#define GSI_MAP_KTYPES	GSUNION_OBJ
#define GSI_MAP_VTYPES	GSUNION_NSINT

#if	GS_WITH_GC
#include	<gc/gc_typed.h>
static GC_descr	nodeDesc;	// Type descriptor for map node.
#define	GSI_MAP_NODES(M, X) \
(GSIMapNode)GC_calloc_explicitly_typed(X, sizeof(GSIMapNode_t), nodeDesc)
#endif

#include "GNUstepBase/GSIMap.h"

@interface GSCountedSet : NSCountedSet
{
@public
  GSIMapTable_t	map;
@private
  NSUInteger _version;
}
@end

@interface GSCountedSetEnumerator : NSEnumerator
{
  GSCountedSet		*set;
  GSIMapEnumerator_t	enumerator;
}
@end

@implementation GSCountedSetEnumerator

- (void) dealloc
{
  GSIMapEndEnumerator(&enumerator);
  RELEASE(set);
  [super dealloc];
}

- (id) initWithSet: (NSSet*)d
{
  self = [super init];
  if (self != nil)
    {
      set = RETAIN((GSCountedSet*)d);
      enumerator = GSIMapEnumeratorForMap(&set->map);
    }
  return self;
}

- (id) nextObject
{
  GSIMapNode node = GSIMapEnumeratorNextNode(&enumerator);

  if (node == 0)
    {
      return nil;
    }
  return node->key.obj;
}

@end


@implementation GSCountedSet

+ (void) initialize
{
  if (self == [GSCountedSet class])
    {
#if	GS_WITH_GC
      /* We create a typed memory descriptor for map nodes.
       * Only the pointer to the key needs to be scanned.
       */
      GC_word	w[GC_BITMAP_SIZE(GSIMapNode_t)] = {0};
      GC_set_bit(w, GC_WORD_OFFSET(GSIMapNode_t, key));
      nodeDesc = GC_make_descriptor(w, GC_WORD_LEN(GSIMapNode_t));
#endif
    }
}

/**
 * Adds an object to the set.  If the set already contains an object
 * equal to the specified object (as determined by the [-isEqual:]
 * method) then the count for that object is incremented rather
 * than the new object being added.
 */
- (void) addObject: (id)anObject
{
  GSIMapNode node;

  if (anObject == nil)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Tried to nil value to counted set"];
    }

  _version++;
  node = GSIMapNodeForKey(&map, (GSIMapKey)anObject);
  if (node == 0)
    {
      GSIMapAddPair(&map,(GSIMapKey)anObject,(GSIMapVal)(NSUInteger)1);
    }
  else
    {
      node->value.nsu++;
    }
  _version++;
}

- (NSUInteger) count
{
  return map.nodeCount;
}

- (NSUInteger) countForObject: (id)anObject
{
  if (anObject)
    {
      GSIMapNode node = GSIMapNodeForKey(&map, (GSIMapKey)anObject);

      if (node)
	{
	  return node->value.nsu;
	}
    }
  return 0;
}

- (void) dealloc
{
  GSIMapEmptyMap(&map);
  [super dealloc];
}

- (void) encodeWithCoder: (NSCoder*)aCoder
{
  unsigned	count = map.nodeCount;
  SEL		sel1 = @selector(encodeObject:);
  IMP		imp1 = [aCoder methodForSelector: sel1];
  SEL		sel2 = @selector(encodeValueOfObjCType:at:);
  IMP		imp2 = [aCoder methodForSelector: sel2];
  const char	*type = @encode(unsigned);
  GSIMapEnumerator_t	enumerator = GSIMapEnumeratorForMap(&map);
  GSIMapNode 		node = GSIMapEnumeratorNextNode(&enumerator);

  (*imp2)(aCoder, sel2, type, &count);

  while (node != 0)
    {
      (*imp1)(aCoder, sel1, node->key.obj);
      (*imp2)(aCoder, sel2, type, &node->value.nsu);
      node = GSIMapEnumeratorNextNode(&enumerator);
    }
  GSIMapEndEnumerator(&enumerator);
}

- (NSUInteger) hash
{
  return map.nodeCount;
}

- (id) init
{
  return [self initWithCapacity: 0];
}

/* Designated initialiser */
- (id) initWithCapacity: (NSUInteger)cap
{
  GSIMapInitWithZoneAndCapacity(&map, [self zone], cap);
  return self;
}

- (id) initWithCoder: (NSCoder*)aCoder
{
  unsigned	count;
  id		value;
  NSUInteger	valcnt;
  SEL		sel = @selector(decodeValueOfObjCType:at:);
  IMP		imp = [aCoder methodForSelector: sel];
  const char	*utype = @encode(unsigned);
  const char	*otype = @encode(id);

  (*imp)(aCoder, sel, utype, &count);

  GSIMapInitWithZoneAndCapacity(&map, [self zone], count);
  while (count-- > 0)
    {
      (*imp)(aCoder, sel, otype, &value);
      (*imp)(aCoder, sel, utype, &valcnt);
      GSIMapAddPairNoRetain(&map, (GSIMapKey)value, (GSIMapVal)valcnt);
    }

  return self;
}

- (id) initWithObjects: (const id[])objs count: (NSUInteger)c
{
  NSUInteger	i;

  self = [self initWithCapacity: c];
  if (self == nil)
    {
      return nil;
    }
  for (i = 0; i < c; i++)
    {
      GSIMapNode     node;

      if (objs[i] == nil)
	{
	  DESTROY(self);
	  [NSException raise: NSInvalidArgumentException
		      format: @"Tried to init counted set with nil value"];
	}
      node = GSIMapNodeForKey(&map, (GSIMapKey)objs[i]);
      if (node == 0)
	{
	  GSIMapAddPair(&map,(GSIMapKey)objs[i],(GSIMapVal)(NSUInteger)1);
        }
      else
	{
	  node->value.nsu++;
	}
    }
  return self;
}

- (id) member: (id)anObject
{
  if (anObject != nil)
    {
      GSIMapNode node = GSIMapNodeForKey(&map, (GSIMapKey)anObject);

      if (node != 0)
	{
	  return node->key.obj;
	}
    }
  return nil;
}

- (NSEnumerator*) objectEnumerator
{
  return AUTORELEASE([[GSCountedSetEnumerator allocWithZone:
    NSDefaultMallocZone()] initWithSet: self]);
}

/**
 * Removes all objcts which have not been added more than level times
 * from the counted set.<br />
 * Note to GNUstep maintainers ... this method depends on the characteristic
 * of the GSIMap enumeration that, once enumerated, an object can be removed
 * from the map.  If GSIMap ever loses that characterstic, this will break.
 */
- (void) purge: (NSInteger)level
{
  if (level > 0)
    {
      GSIMapEnumerator_t	enumerator = GSIMapEnumeratorForMap(&map);
      GSIMapBucket       	bucket = GSIMapEnumeratorBucket(&enumerator);
      GSIMapNode 		node = GSIMapEnumeratorNextNode(&enumerator);

      while (node != 0)
	{
	  if (node->value.nsu <= (NSUInteger)level)
	    {
	      _version++;
	      GSIMapRemoveNodeFromMap(&map, bucket, node);
	      GSIMapFreeNode(&map, node);
	      _version++;
	    }
	  bucket = GSIMapEnumeratorBucket(&enumerator);
	  node = GSIMapEnumeratorNextNode(&enumerator);
	}
      GSIMapEndEnumerator(&enumerator);
    }
}

- (void) removeAllObjects
{
  _version++;
  GSIMapCleanMap(&map);
  _version++;
}

/**
 * Decrements the count of the number of times that the specified
 * object (or an object equal to it as determined by the
 * [-isEqual:] method) has been added to the set.  If the count
 * becomes zero, the object is removed from the set.
 */
- (void) removeObject: (id)anObject
{
  GSIMapBucket       bucket;

  if (anObject == nil)
    {
      NSWarnMLog(@"attempt to remove nil object");
      return;
    }
  _version++;
  bucket = GSIMapBucketForKey(&map, (GSIMapKey)anObject);
  if (bucket != 0)
    {
      GSIMapNode     node;

      node = GSIMapNodeForKeyInBucket(&map, bucket, (GSIMapKey)anObject);
      if (node != 0)
	{
	  if (--node->value.nsu == 0)
	    {
	      GSIMapRemoveNodeFromMap(&map, bucket, node);
	      GSIMapFreeNode(&map, node);
	    }
	}
    }
  _version++;
}

- (id) unique: (id)anObject
{
  GSIMapNode	node;
  id		result;
  _version++;

  if (anObject == nil)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Tried to unique nil value in counted set"];
    }

  node = GSIMapNodeForKey(&map, (GSIMapKey)anObject);
  if (node == 0)
    {
      result = anObject;
      GSIMapAddPair(&map,(GSIMapKey)anObject,(GSIMapVal)(NSUInteger)1);
    }
  else
    {
      result = node->key.obj;
      node->value.nsu++;
#if	!GS_WITH_GC
      if (result != anObject)
	{
	  [anObject release];
	  [result retain];
	}
#endif
    }
  _version++;
  return result;
}

- (NSUInteger) countByEnumeratingWithState: (NSFastEnumerationState*)state
                                   objects: (id*)stackbuf
                                     count: (NSUInteger)len
{
  state->mutationsPtr = (unsigned long *)&_version;
  return GSIMapCountByEnumeratingWithStateObjectsCount
    (&map, state, stackbuf, len);
}

- (NSUInteger) sizeInBytesExcluding: (NSHashTable*)exclude
{
  NSUInteger	size = GSPrivateMemorySize(self, exclude);

  if (size > 0)
    {
      GSIMapEnumerator_t	enumerator = GSIMapEnumeratorForMap(&map);
      GSIMapNode 		node = GSIMapEnumeratorNextNode(&enumerator);

      size += GSIMapSize(&map) - sizeof(map);
      while (node != 0)
        {
          size += [node->key.obj sizeInBytesExcluding: exclude];
          node = GSIMapEnumeratorNextNode(&enumerator);
        }
      GSIMapEndEnumerator(&enumerator);
    }
  return size;
}

@end
