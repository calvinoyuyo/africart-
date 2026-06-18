import React from "react";

interface WishItemProps {
  id: string;
  title: string;
  price: number;
  image: string;
  slug: string;
  stockAvailabillity: number;
}

const WishItem = ({ id, title, price, image, slug, stockAvailabillity }: WishItemProps) => {
  return (
    <div className="flex items-center gap-4 p-4 border-b">
      <img src={image} alt={title} className="w-16 h-16 object-cover" />
      <div>
        <p className="font-medium">{title}</p>
        <p className="text-gray-500">${price}</p>
      </div>
    </div>
  );
};

export default WishItem;
